/*
 * Copyright 2022 InfAI (CC SES)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 */

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/shared/account_epoch.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/exceptions/auth_exception.dart';
import 'package:mobile_app/services/api_available.dart';
import 'package:mobile_app/services/favorites_migration.dart';
import 'package:mobile_app/services/fcm_token.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/dio_factory.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mutex/mutex.dart';
import 'package:openidconnect/openidconnect.dart';
import 'package:mobile_app/services/cache_helper.dart';

class Auth extends ChangeNotifier {
  static final _instance = Auth._internal();

  /// Set only by golden/unit tests, to skip the real OIDC client entirely.
  @visibleForTesting
  static Future<Map<String, String>> Function()? headersOverride;

  bool isInitialized = false;

  factory Auth() => _instance;

  Auth._internal() {
    ApiAvailableService.platformUnreachable.addListener(_onReachabilityChanged);
  }

  /// Bounds the client setup: OpenIdConnectClient.create fetches the discovery
  /// document with retries and no timeout of its own.
  @visibleForTesting
  static Duration clientSetupTimeout = const Duration(seconds: 5);

  /// Bounds a token refresh, which runs the same unbounded requests.
  @visibleForTesting
  static Duration tokenRefreshTimeout = const Duration(seconds: 5);

  /// Bounds the setup and refresh of a login the user started, in place of
  /// [clientSetupTimeout] and [tokenRefreshTimeout].
  @visibleForTesting
  static Duration loginTimeout = const Duration(seconds: 30);

  /// Bounds the token revocation of a logout.
  @visibleForTesting
  static Duration logoutTimeout = const Duration(seconds: 5);

  /// After a failed client setup, the next one waits this long unless the
  /// user starts it.
  static const setupRetryInterval = Duration(seconds: 30);

  static final _stopwatch = Stopwatch()..start();
  static Duration _elapsed() => _stopwatch.elapsed;

  /// Monotonic time for [setupRetryInterval].
  @visibleForTesting
  static Duration Function() monotonicNow = _elapsed;

  /// Replaces OpenIdConnectClient.create in the client setup.
  @visibleForTesting
  static Future<OpenIdConnectClient> Function()? createClientOverride;

  Duration? _setupFailedAt;

  /// The client setup still running, also after its caller gave up on it. A
  /// setup that starts meanwhile waits on it instead of starting a second.
  _Setup? _runningSetup;

  /// Set by every logout, cleared by a completed login with credentials.
  /// While set, an identity in the storage or in a new client is not trusted:
  /// an abandoned refresh can still store the signed-out account's identity.
  bool _signedOut = false;

  /// Counts the completed logins with credentials.
  int _logins = 0;

  /// Advanced by every login and logout. An operation abandoned on its
  /// timeout compares it to tell whether the session it ran for still exists.
  int _sessionChanges = 0;

  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,),
  );
  static const encKeyName = 'openid_encryption_key';

  Future<String> _getOrCreateEncryptionKey() async {
    final existing = await _storage.read(key: encKeyName);
    if (existing != null) return existing;

    const chars = 'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890';
    final rnd = Random.secure();
    final newKey = List.generate(32, (_) => chars[rnd.nextInt(chars.length)]).join();
    await _storage.write(key: encKeyName, value: newKey);
    return newKey;
  }

  static final _logger = Logger(
    printer: SimplePrinter(),
  );
  final _m = Mutex();
  final _clientSetupMutex = Mutex();

  /// Serializes [_rememberAccount]: the login and the OIDC event it raises
  /// both report the new identity, and two switches at once would each wipe.
  final _accountMutex = Mutex();

  /// The listener of the current client's events, cancelled when the client
  /// is dropped: its late events would act on the next client.
  StreamSubscription<AuthEvent>? _clientEvents;

  static DateTime? _lastOnlineCheck;
  static const Duration _checkCacheDuration = Duration(seconds: 30);
  static bool _checkCache = false;

  OpenIdConnectClient? _client;

  bool loggedIn = false;

  /// From the current settings: the auth server can be changed at runtime.
  String get discoveryUrl =>
      "${Settings.getKeycloakUrl() ?? 'https://localhost'}/auth/realms/${dotenv.env['KEYCLOAK_REALM'] ?? 'master'}/.well-known/openid-configuration";

  void _onReachabilityChanged() {
    if (!ApiAvailableService.isPlatformUnreachable) {
      // Set up and check again right away rather than sending a stored token
      // that may have expired meanwhile.
      _setupFailedAt = null;
      _lastOnlineCheck = null;
    }
    notifyListeners();
  }

  Future<void> init() => _init(retryNow: true, bound: clientSetupTimeout);

  /// [retryNow] false leaves the setup alone within [setupRetryInterval] of a
  /// failed one. [bound] limits the wait for the setup, not the setup itself.
  Future<void> _init({required bool retryNow, required Duration bound}) async {
    // Trust a stored identity before the client setup: the OIDC discovery in
    // OpenIdConnectClient.create is a network round trip that held the login
    // spinner on every app start. The offline fallback below has always
    // trusted the stored token when the setup fails; trusting it while the
    // setup is still running is the same assumption, just earlier. Backend
    // calls still wait for the real client via getHeaders() -> refreshToken()
    // -> init(), which blocks on the setup mutex.
    if (!isInitialized && !loggedIn && !_signedOut) {
      try {
        final identity = await OpenIdIdentity.load();
        if (identity != null) {
          await _rememberAccount(identity);
          loggedIn = true;
          isInitialized = true;
          notifyListeners();
        }
      } catch (_) {
        // unreadable storage — leave the decision to the regular setup
      }
    }
    await _clientSetupMutex.protect(() async {
      if (_initialized) return;
      final failedAt = _setupFailedAt;
      if (!retryNow &&
          failedAt != null &&
          monotonicNow() - failedAt < setupRetryInterval) {
        return;
      }
      final epoch = ApiAvailableService.reachabilityEpoch;
      // A setup can hang for good (a connection that never answers), so only
      // a recent one for the current URL is joined.
      final running = _runningSetup;
      final setup = running != null &&
              !running.handled &&
              running.url == discoveryUrl &&
              monotonicNow() - running.startedAt < loginTimeout
          ? running
          : await _startSetup();
      var timedOut = false;
      try {
        final start = DateTime.now();
        // The mutex is released on the timeout; the setup goes on and is
        // settled when it ends (_settleSetup).
        final client = await setup.client.timeout(bound, onTimeout: () {
          timedOut = true;
          throw TimeoutException("Client setup", bound);
        });
        setup.handled = true;
        _logger.d("OpenIdConnectClient.create ${DateTime.now().difference(start)}");
        await _adoptClient(client);
      } catch (e) {
        // Offline or server unreachable — fall back to cached token
        _logger.d("Client setup failed (offline?): $e");
        if (!timedOut) setup.handled = true;
        _setupFailedAt = monotonicNow();
        // A slow or failing auth server alone is no outage; a transport
        // error is.
        if (timedOut || e is TimeoutException || e is HttpException) {
          unawaited(
              ApiAvailableService().confirmUnreachable(observedAt: epoch));
        } else if (e is IOException) {
          ApiAvailableService().markPlatformUnreachable(observedAt: epoch);
        }
        if (!loggedIn && !_signedOut) {
          final token = await OpenIdIdentity.load();
          if (token != null) {
            _logger.d("Using token from storage, assuming still valid");
            await _rememberAccount(token);
            loggedIn = true;
            notifyListeners();
          }
        }
      }
    });
    isInitialized = true;
    notifyListeners();
  }

  bool get _initialized => _client != null;

  Future<_Setup> _startSetup() async {
    final sessions = _sessionChanges;
    OpenIdIdentity? before;
    try {
      before = await OpenIdIdentity.load();
    } catch (_) {}
    final setup = _Setup(
        _createClient(), sessions, before, discoveryUrl, monotonicNow());
    _runningSetup = setup;
    unawaited(_settleSetup(setup));
    return setup;
  }

  /// Takes [client] as the session's client, as a setup that ended in time.
  Future<void> _adoptClient(OpenIdConnectClient client) async {
    _client = client;
    _setupFailedAt = null;
    if (_signedOut) {
      // No login since the logout stored what the client found.
      try {
        await client.clearIdentity();
        await OpenIdIdentity.clear();
      } catch (e) {
        _logger.w("Could not clear identity: $e");
      }
    }
    // The auth server answered, so an outage mark may be stale; checked
    // before the session's first requests would be refused for it.
    if (ApiAvailableService.isPlatformUnreachable) {
      await ApiAvailableService().recheckPlatform();
    }
    await _rememberAccount(_client?.identity);
    loggedIn = _client?.identity != null;
    notifyListeners();
    if (_clientEvents == null && _client != null) {
      _clientEvents = _client!.changes.listen(_onClientEvent);
    }
  }

  /// Runs once [setup] ends. A client that no caller took in time is adopted
  /// while the session it started in still has none, and disposed of
  /// otherwise.
  Future<void> _settleSetup(_Setup setup) async {
    OpenIdConnectClient? client;
    try {
      client = await setup.client;
    } catch (_) {}
    final discarded = await _clientSetupMutex.protect(() async {
      if (identical(_runningSetup, setup)) _runningSetup = null;
      if (setup.handled) return false;
      setup.handled = true;
      if (client != null &&
          _client == null &&
          _sessionChanges == setup.sessions) {
        _logger.d("Adopting a client set up late");
        await _adoptClient(client);
        return false;
      }
      client?.dispose();
      return true;
    });
    // Outside the setup mutex: the reconcile takes _m, which is taken first
    // everywhere else.
    if (discarded) {
      _afterAbandoned(Future.value(), setup.sessions, setup.before);
    }
  }

  Future<OpenIdConnectClient> _createClient() async {
    if (createClientOverride != null) return createClientOverride!();
    final encKey = await _getOrCreateEncryptionKey();
    return OpenIdConnectClient.create(
      discoveryDocumentUrl: discoveryUrl,
      clientId: dotenv.env['KEYCLOAK_CLIENTID'] ?? 'optimise_mobile_app',
      encryptionKey: encKey,
      redirectUrl: Settings.getKeycloakRedirect() ?? "https://localhost",
      scopes: [
        OpenIdConnectClient.OFFLINE_ACCESS_SCOPE,
        ...OpenIdConnectClient.DEFAULT_SCOPES
      ],
      autoRefresh: false,
    );
  }

  /// Drops [client] like an offline logout does, without touching the
  /// session: its late events must not act on the next client.
  Future<void> _abandonClient(OpenIdConnectClient client) async {
    if (!identical(_client, client)) return;
    _client = null;
    _setupFailedAt = monotonicNow();
    await _clientEvents?.cancel();
    _clientEvents = null;
  }

  /// An operation abandoned on its timeout can still save a refreshed
  /// identity or clear the stored one when it ends. Once [settled] completes,
  /// the stored identity is made to match the session again. [before] is the
  /// identity the operation started from.
  void _afterAbandoned(
      Future<void> settled, int sessions, OpenIdIdentity? before) {
    unawaited(settled
        .catchError((Object e) => _logger.d("Abandoned auth call failed: $e"))
        .then((_) => _m.protect(() async {
              try {
                await _reconcileStoredIdentity(sessions, before);
              } catch (e) {
                _logger.w("Could not restore the stored identity: $e");
              }
            })));
  }

  Future<void> _reconcileStoredIdentity(
      int sessions, OpenIdIdentity? before) async {
    final current = _client?.identity;
    if (_sessionChanges != sessions) {
      // A login or logout came after: what the late call stored is not this
      // session's.
      if (current != null) {
        await current.save();
      } else if (!loggedIn) {
        await OpenIdIdentity.clear();
      }
      return;
    }
    // Same session: a refreshed identity it stored is kept, one it cleared on
    // a failure is put back.
    if (!loggedIn || await OpenIdIdentity.load() != null) return;
    await (current ?? before)?.save();
  }

  /// [OpenIdConnectClient.refresh], bounded by [bound]. On the timeout the
  /// client is abandoned, so its late result reaches neither the session nor
  /// the next client.
  Future<bool> _refreshBounded(
      OpenIdConnectClient client, Duration bound) async {
    final epoch = ApiAvailableService.reachabilityEpoch;
    final sessions = _sessionChanges;
    final before = client.identity;
    final pending = client.refresh();
    var timedOut = false;
    final ok = await pending.timeout(bound, onTimeout: () {
      timedOut = true;
      return false;
    });
    if (timedOut) {
      unawaited(ApiAvailableService().confirmUnreachable(observedAt: epoch));
      await _abandonClient(client);
      _afterAbandoned(pending.then((_) => client.dispose()), sessions, before);
    }
    return ok;
  }

  /// [OpenIdConnectClient.loginWithPassword], bounded by [loginTimeout]. On
  /// the timeout the client is abandoned, and an identity the late login
  /// stores is removed again unless a session began meanwhile.
  Future<OpenIdIdentity?> _loginBounded(
      OpenIdConnectClient client, String user, String pw) async {
    final sessions = _sessionChanges;
    // Widened, so the timeout below can answer null.
    final pending = client
        .loginWithPassword(userName: user, password: pw, prompts: ["none"])
        .then<OpenIdIdentity?>((identity) => identity);
    var timedOut = false;
    final token = await pending.timeout(loginTimeout, onTimeout: () {
      timedOut = true;
      return null;
    });
    if (!timedOut) return token;
    await _abandonClient(client);
    unawaited(pending
        .then((_) {}, onError: (Object e) => _logger.d("Late login failed: $e"))
        .then((_) => _m.protect(() async {
              client.dispose();
              try {
                if (_sessionChanges == sessions && !loggedIn) {
                  await OpenIdIdentity.clear();
                } else {
                  await _reconcileStoredIdentity(sessions, null);
                }
              } catch (e) {
                _logger.w("Could not clear a late login: $e");
              }
            })));
    throw AuthException("Can't login, are you online?");
  }

  Future<void> _onClientEvent(AuthEvent event) async {
    _logger.d("${event.type}: ${event.message}");
    switch (event.type) {
      case AuthEventTypes.Refresh:
      case AuthEventTypes.Success:
        // Signed out, an identity comes only from a login with credentials,
        // which sets the session up itself.
        if (_signedOut) break;
        await _rememberAccount(_client?.identity);
        loggedIn = true;
        notifyListeners();
        break;
      case AuthEventTypes.NotLoggedIn:
        // The logout that signed out has cleaned up already.
        if (_signedOut) break;
        loggedIn = _client?.identity != null;
        notifyListeners();
        if (!loggedIn) await _cleanup();
        notifyListeners();
        break;
      case AuthEventTypes.Error:
      case AuthEventTypes.LoggingOut:
        await _onLogout();
    }
  }

  // Written before loggedIn flips, because the tabs mount on that flag and read
  // the per-account favorites right away. Never cleared on logout: the
  // favorites are keyed by it and have to survive until that account returns.
  //
  // This is also the one place that sees an account actually change, which is
  // what the cache wipe below hangs on. Keying it on the identity just obtained
  // rather than on loggedIn matters: at the login path loggedIn is set by the
  // OIDC event listener, so a check placed there fires too late.
  Future<void> _rememberAccount(OpenIdIdentity? identity) async {
    if (identity == null) return;
    try {
      await _accountMutex.protect(() async {
        final previous = Settings.getAccount();
        if (previous == null || previous == identity.sub) {
          await Settings.setAccount(identity.sub);
          // A switch whose wipe did not complete. The rows of this account it
          // drops too are refilled by the next refresh.
          await CacheHelper.retryPendingAccountWipe();
          return;
        }
        // Under the outgoing account, which owns what these move; neither
        // failing may keep the next account in the previous one's state.
        try {
          await FavoritesMigration.run();
        } catch (e, s) {
          ErrorReporter.log("Could not move the favorites off the cache", e, s);
        }
        try {
          await Settings.moveLegacyAccountSettings();
        } catch (e, s) {
          ErrorReporter.log("Could not move the unkeyed settings", e, s);
        }
        await CacheHelper.switchAccount(identity.sub);
        _logger.d("Account changed, dropped the previous account's cache");
      });
    } catch (e) {
      // Never let this escape: init() runs it on the path that decides whether
      // the app gets past the login spinner at all.
      _logger.w("Could not switch account cleanly: $e");
    }
  }

  Future<void> login(String user, String pw) async {
    await _m.protect(() async {
      // loggingIn (== mutex held) just became true; without this notify the
      // login form stays frozen with no feedback until the grant completes.
      notifyListeners();
      if (!_initialized) {
        await _init(retryNow: true, bound: loginTimeout);
        if (_client == null) {
          throw AuthException("Can't login, are you online?");
        }
      }

      if (tokenValid) {
        _logger.d("Old token still valid");
        return;
      }
      if (await __refresh(bound: loginTimeout)) {
        _logger.d("refreshed token");
        return;
      }
      // A refresh that timed out abandoned the client.
      if (_client == null) {
        throw AuthException("Can't login, are you online?");
      }
      final OpenIdIdentity? token;
      try {
        token = await _loginBounded(_client!, user, pw);
      } catch (e) {
        _logger.e("Login failed: $e");
        rethrow;
      }

      if (token != null) {
        _logger.i('Logged in');
        _signedOut = false;
        _logins++;
        _sessionChanges++;
        await _rememberAccount(token);
        loggedIn = true;
        notifyListeners();
        //await AppState().initMessaging();
      } else {
        _logger.w("_token null");
        throw AuthException("token null");
      }
      return;
    });
  }

  logout(BuildContext context) async {
    // In an outage the setup could only run into its bound.
    if (!_initialized && !ApiAvailableService.platformCallsOff) {
      await init();
    }
    if (_client == null && loggedIn) {
      // Signed in on the stored token alone, the client setup having failed:
      // log out without revoking, as after the client's own logout event.
      await _onLogout();
      if (!context.mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    if (_client?.identity == null) {
      return;
    }
    if (ApiAvailableService.isPlatformUnreachable) {
      // The revocation could only run into its bound.
      await _onLogout(offline: true);
      if (!context.mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }

    if (AppState().fcmToken != null) {
      // Never block the logout on this: an unreachable backend used to abort
      // logout here, leaving the user signed in with no way out. A token that
      // could not be deregistered stops receiving pushes anyway, because the
      // next login registers a fresh one.
      try {
        await FcmTokenService.deregisterFcmToken(AppState().fcmToken!);
      } catch (e) {
        _logger.w("Could not deregister FCM token: $e");
      }
    }

    final client = _client!;
    final logins = _logins;
    final pending = client.logout();
    var timedOut = false;
    await pending.timeout(logoutTimeout, onTimeout: () => timedOut = true);
    _logger.d("logout");
    if (timedOut) {
      // The revocation hangs: logged out without it, as when offline, unless
      // a login came meanwhile. The client's own late clear then finds no
      // identity left.
      if (_logins == logins) {
        try {
          await client.clearIdentity();
        } catch (e) {
          _logger.w("Could not clear identity: $e");
        }
        await _onLogout(offline: true);
      }
      unawaited(pending
          .catchError((Object e) => _logger.d("Late logout failed: $e"))
          .whenComplete(() {
        if (!identical(_client, client)) client.dispose();
      }));
    } else if (_client == null || identical(_client, client)) {
      // Offline the client's own events were cancelled with it. Not when a
      // new session began while this revoke was in flight.
      await _cleanup();
      loggedIn = false;
      notifyListeners();
    }
    if (!context.mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// [offline] skips the server check, the server being known not to answer.
  _onLogout({bool offline = false}) async {
    _sessionChanges++;
    _signedOut = true;
    if (!offline && await _serverAvailable()) {
      await _cleanup();
    } else {
      final client = _client;
      _client = null;
      await _clientEvents?.cancel();
      _clientEvents = null;
      // Not revocable offline, but the stored tokens must not sign the next
      // login back in, whatever credentials it was given. Through the client
      // when there is one: it forgets its identity too, so its own logout,
      // still running, cannot clear the next session's stored one.
      try {
        if (client != null) {
          await client.clearIdentity();
        } else {
          await OpenIdIdentity.clear();
        }
      } catch (e) {
        _logger.w("Could not clear identity: $e");
      }
    }
    loggedIn = false;
    notifyListeners();
  }

  /// Runs the logout cleanup without a signed-in client.
  @visibleForTesting
  Future<void> cleanupForTest() => _cleanup();

  /// Replaces the server check of the logout, so a test can log out offline.
  @visibleForTesting
  static Future<bool> Function()? serverAvailableOverride;

  /// Runs the logout that follows the client's logout or error event.
  @visibleForTesting
  Future<void> onLogoutForTest() => _onLogout();

  /// Records [identity] as signed in, as every sign-in path does before
  /// [loggedIn] flips.
  @visibleForTesting
  Future<void> rememberAccountForTest(OpenIdIdentity identity) =>
      _rememberAccount(identity);

  /// Whether the client's events have a listener; the next client setup
  /// registers one when not.
  @visibleForTesting
  bool get clientListenerRegistered => _clientEvents != null;

  /// Listens to [events] as to the events of a set-up client.
  @visibleForTesting
  void listenToClientEventsForTest(Stream<AuthEvent> events) =>
      _clientEvents = events.listen(_onClientEvent);

  /// Forgets the client and a failed setup without logging out.
  @visibleForTesting
  Future<void> resetForTest() async {
    _client = null;
    await _clientEvents?.cancel();
    _clientEvents = null;
    _setupFailedAt = null;
    _runningSetup = null;
    _signedOut = false;
    loggedIn = false;
    isInitialized = false;
  }

  Future<void> _cleanup() async {
    _sessionChanges++;
    _signedOut = true;
    AccountEpoch.advance();
    await CacheHelper.clearCache();
    await AppState().onLogout();
    if (_client != null) {
      // Awaited, not slept on: clearIdentity returns a Future since
      // openidconnect 2.0. The old fixed 2s wait predates that upgrade and
      // neither guaranteed completion nor bounded the logout.
      // Swallowed like the package does in _clearIdentityIgnoringErrors: an
      // unusable Keystore entry must not stop the logout half-way, or the user
      // stays logged in with no way back.
      try {
        await _client!.clearIdentity();
      } catch (e) {
        _logger.w("Could not clear identity: $e");
      }
    } else {
      await OpenIdIdentity.clear(); // remove saved token
    }
    await _storage.delete(key: encKeyName);
  }

  Future<Map<String, String>> getHeaders() async {
    if (headersOverride != null) return headersOverride!();
    if (!loggedIn) {
      notifyListeners();
      throw AuthException("Not logged in");
    }
    if (ApiAvailableService.platformCallsOff) {
      // Nothing waits on the auth server here: the interceptor refuses the
      // platform requests, and a gateway request gets the stored token.
      return _storedHeaders();
    }
    if (!(await refreshToken())) {
      return {};
    }
    return {"authorization": "Bearer ${await getToken()}", "content-type": Headers.jsonContentType};
  }

  Future<Map<String, String>> _storedHeaders() async {
    var token = _client?.identity?.accessToken;
    if (token == null) {
      try {
        token = (await OpenIdIdentity.load())?.accessToken;
      } catch (e) {
        _logger.w("Could not read the stored identity: $e");
      }
    }
    if (token == null) return {};
    return {"authorization": "Bearer $token", "content-type": Headers.jsonContentType};
  }

  Future<bool> refreshToken({bool skipLock = false}) async {
    if (skipLock) {
      return await __refresh();
    }
    return await _m.protect(__refresh);
  }

  /// [bound] replaces [clientSetupTimeout] and [tokenRefreshTimeout].
  Future<bool> __refresh({Duration? bound}) async {
    if (!_initialized) {
      await _init(retryNow: false, bound: bound ?? clientSetupTimeout);
    }
    if (tokenValid) return true;
    final client = _client;
    if (client != null && client.identity != null && client.hasTokenExpired == true && (await _serverAvailable())) {
      final ok = await _refreshBounded(client, bound ?? tokenRefreshTimeout);
      return ok && tokenValid;
    }
    return false;
  }

  bool get tokenValid => loggedIn && (_client == null || (_client!.identity != null && !_client!.hasTokenExpired)); //assumed logged in when offline

  bool get loggingIn => _m.isLocked;

  Future<String> getToken() async {
    if (_client != null) {
      return _client!.identity!.accessToken;
    }
    final token = await OpenIdIdentity.load();
    if (token != null) {
      return token.accessToken;
    }
    return "";
  }

  String? getUsername() {
    return _client?.identity?.userName;
  }

  Future<bool> _serverAvailable() async {
    if (serverAvailableOverride != null) return serverAvailableOverride!();
    if (_lastOnlineCheck != null && DateTime.now().difference(_lastOnlineCheck!) < _checkCacheDuration) {
      return _checkCache;
    }
    // checkConnectivity returns a List since connectivity_plus 6, so comparing
    // it to a single value was always false and this fast path never fired -
    // an offline logout waited out the 5s connect timeout below instead.
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.isEmpty ||
        connectivity.contains(ConnectivityResult.none)) {
      _checkCache = false;
      _lastOnlineCheck = DateTime.now();
      return false;
    }
    try {
      final dio = await DioFactory.create(DioConfig.standard);
      final resp = await dio.get(discoveryUrl);
      _checkCache = resp.statusCode == 200;
    } catch (e) {
      _checkCache = false;
    } finally {
      _lastOnlineCheck = DateTime.now();
    }
    return _checkCache;
  }
}

/// A client setup and the session it started in.
class _Setup {
  _Setup(this.client, this.sessions, this.before, this.url, this.startedAt);

  final Future<OpenIdConnectClient> client;

  /// The discovery URL it was started with.
  final String url;

  /// [Auth.monotonicNow] when it started.
  final Duration startedAt;

  /// [Auth._sessionChanges] when it started.
  final int sessions;

  /// The stored identity when it started.
  final OpenIdIdentity? before;

  /// Set once a caller or [Auth._settleSetup] dealt with its outcome.
  bool handled = false;
}
