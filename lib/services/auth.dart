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
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
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
import 'package:oauth2/oauth2.dart' as oauth2;
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/live/client_certificate.dart';
import 'package:mobile_app/live/live_values.dart';

/// Signs in with the password grant and keeps the session until Keycloak
/// refuses its refresh token with `invalid_grant`.
class Auth extends ChangeNotifier with WidgetsBindingObserver {
  static final _instance = Auth._internal();

  /// Set only by golden/unit tests, to skip the auth server entirely.
  @visibleForTesting
  static Future<Map<String, String>> Function()? headersOverride;

  bool isInitialized = false;

  factory Auth() => _instance;

  Auth._internal() {
    ApiAvailableService.platformUnreachable.addListener(_onReachabilityChanged);
  }

  /// Bounds the discovery a background refresh needs for credentials stored
  /// without their token endpoint.
  @visibleForTesting
  static Duration clientSetupTimeout = const Duration(seconds: 5);

  /// Bounds a token refresh.
  @visibleForTesting
  static Duration tokenRefreshTimeout = const Duration(seconds: 5);

  /// Bounds the discovery, the refresh and the password grant of a login the
  /// user started, in place of [clientSetupTimeout] and [tokenRefreshTimeout].
  @visibleForTesting
  static Duration loginTimeout = const Duration(seconds: 30);

  /// Bounds the discovery and token revocation of a logout.
  @visibleForTesting
  static Duration logoutTimeout = const Duration(seconds: 5);

  /// Bounds each read of the stored credentials: the Android plugin never
  /// answers a call that ran into a FileNotFoundException. Past it the read
  /// counts as failed, and a late answer is dropped.
  @visibleForTesting
  static Duration storageReadTimeout = const Duration(seconds: 5);

  /// After a failed discovery, the next one waits this long unless the user
  /// starts it.
  static const setupRetryInterval = Duration(seconds: 30);

  static final _stopwatch = Stopwatch()..start();
  static Duration _elapsed() => _stopwatch.elapsed;

  /// Monotonic time for [setupRetryInterval].
  @visibleForTesting
  static Duration Function() monotonicNow = _elapsed;

  /// Makes the client of each request to the auth server.
  @visibleForTesting
  static http.Client Function() httpClient = http.Client.new;

  /// The toast text of a login Keycloak refused for its credentials.
  static const invalidCredentials = "Invalid user credentials";

  /// The messages a sign-in with a code ends with.
  static const codeLoginDeclined = "Sign-in was declined";
  static const codeExpired = "The code has expired";
  static const codeLoginDisabled =
      "Sign-in with a code is not enabled on the server";
  static const codeLoginUnavailable =
      "Sign-in with a code is not offered by the server";

  static const _offline = "Can't login, are you online?";
  static const _unexpectedAnswer = "Unexpected answer from the auth server";

  /// What one second of a device authorization lasts: its lifetime, its
  /// poll interval and the slow_down step.
  @visibleForTesting
  static Duration deviceSecond = const Duration(seconds: 1);

  /// Caps the lifetime and the poll interval a server gives, so that the
  /// conversion to a [Duration] cannot overflow.
  static const _maxDeviceSeconds = 86400;

  // Without resetOnError, as every store of the app: on Android they share
  // one file, and a reset after a read error would delete these credentials.
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _credentialsKey = 'auth_credentials';

  /// Set once the identity of the openidconnect package is moved or known to
  /// be absent; it is never read again after.
  static const _legacyMigratedKey = 'auth_legacy_migrated';

  /// No longer written, and deleted with the previous identity.
  static const encKeyName = 'openid_encryption_key';

  /// The storage keys of the credentials and of the migration mark.
  @visibleForTesting
  static const storageKeys = (credentials: _credentialsKey, legacyMigrated: _legacyMigratedKey);

  /// The openidconnect package's storage, read directly: its own
  /// OpenIdIdentity.load clears the identity on any read error.
  static const _legacyStorage =
      MethodChannel('plugins.concerti.io/openidconnect_secure_storage');
  static const _legacyKeys = [
    'ACCESS_TOKEN',
    'ID_TOKEN',
    'REFRESH_TOKEN',
    'EXPIRES_ON',
    'TOKEN_TYPE',
    'STATE',
  ];

  static const _scopes = ['offline_access', 'openid', 'profile', 'email'];

  static String get _clientId =>
      dotenv.env['KEYCLOAK_CLIENTID'] ?? 'optimise_mobile_app';

  static final _logger = Logger(
    printer: SimplePrinter(),
  );
  final _m = Mutex();

  /// Serializes the reads of the stored credentials, and the migration.
  final _loadMutex = Mutex();

  /// Orders the writes of the credentials against their deletion.
  final _storeMutex = Mutex();

  /// Serializes [_rememberAccount]: two switches at once would each wipe.
  final _accountMutex = Mutex();

  static DateTime? _lastOnlineCheck;
  static const Duration _checkCacheDuration = Duration(seconds: 30);
  static bool _checkCache = false;

  oauth2.Credentials? _credentials;

  bool loggedIn = false;

  /// Whether the storage answered a read of the credentials. A read that
  /// failed, as on an iPhone before its first unlock, leaves it false and
  /// deletes nothing, so the next call reads again.
  bool _loaded = false;

  /// Whether the last read of the credentials failed; only then does a call
  /// without a session read again.
  bool _readFailed = false;

  /// Set by every logout, cleared by a completed login with credentials.
  /// While set, the storage is not read: a deletion that failed would sign
  /// the logged-out account back in. [Settings.getSignedOut] does the same
  /// across starts.
  bool _signedOut = false;

  /// Advanced by every login and logout. An operation that ends late compares
  /// it to tell whether the session it ran for still exists.
  int _sessionChanges = 0;

  /// Discovery results by discovery URL.
  final _discoveries = <String, _Discovery>{};
  _RunningDiscovery? _runningDiscovery;
  Duration? _discoveryFailedAt;

  /// The cleanup of the last logout while it runs; a login waits for it.
  Future<void>? _cleaning;

  /// The retry of a pending account wipe while it runs.
  Future<void>? _wipeRetry;

  /// The refresh request still running, also after its caller gave up on it.
  /// A refresh of the same credentials waits on it instead of sending their
  /// refresh token a second time, unless it is older than [loginTimeout].
  _Refresh? _refreshing;

  /// The sign-in with a code while it runs; one at a time.
  _CodeLogin? _codeLogin;

  bool _observingLifecycle = false;

  /// From the current settings: the auth server can be changed at runtime.
  String get discoveryUrl =>
      "${Settings.getKeycloakUrl() ?? 'https://localhost'}/auth/realms/${dotenv.env['KEYCLOAK_REALM'] ?? 'master'}/.well-known/openid-configuration";

  void _onReachabilityChanged() {
    if (!ApiAvailableService.isPlatformUnreachable) {
      // Discover and check again right away rather than sending a stored
      // token that may have expired meanwhile.
      _discoveryFailedAt = null;
      _lastOnlineCheck = null;
    }
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A start in the background on a locked iPhone may not have read the
    // credentials yet.
    if (state == AppLifecycleState.resumed && _readFailed) {
      unawaited(_ensureLoaded());
    }
  }

  /// Reads the stored credentials; no request to the auth server.
  Future<void> init() async {
    if (!_observingLifecycle) {
      _observingLifecycle = true;
      WidgetsBinding.instance.addObserver(this);
    }
    await _ensureLoaded();
    isInitialized = true;
    notifyListeners();
  }

  Future<void> _ensureLoaded() async {
    if (_loaded || _signedOut || _credentials != null) return;
    await _loadMutex.protect(() async {
      if (_loaded || _signedOut || _credentials != null) return;
      final sessions = _sessionChanges;
      final credentials = await _readCredentials(sessions);
      _readFailed = !_loaded;
      if (credentials == null || _sessionChanges != sessions) return;
      _credentials = credentials;
      await _rememberAccount(_subjectOf(credentials));
      if (_sessionChanges != sessions) return;
      loggedIn = true;
      // The session is there; a sign-in with a code would only be dropped.
      cancelCodeLogin();
      notifyListeners();
    });
  }

  /// The stored credentials, or the openidconnect package's identity moved
  /// over when there are none. Sets [_loaded] once the storage answered.
  Future<oauth2.Credentials?> _readCredentials(int sessions) async {
    if (_signedOutMarked()) {
      // Neither stored nor previous credentials sign in after a logout whose
      // deletion failed or did not take; it is tried again instead.
      _loaded = true;
      unawaited(_deleteStored(sessions));
      return null;
    }
    String? stored;
    String? migrated;
    try {
      stored = await _storage
          .read(key: _credentialsKey)
          .timeout(storageReadTimeout);
      if (stored == null && _credentialsMarked()) {
        // The iOS Keychain answers nothing instead of failing before the
        // first unlock; read as a failed read.
        _logger.w("Stored credentials not readable yet");
        return null;
      }
      if (stored == null) {
        migrated = await _storage
            .read(key: _legacyMigratedKey)
            .timeout(storageReadTimeout);
      }
    } catch (e) {
      _logger.w("Could not read the stored credentials: ${e.runtimeType}");
      return null;
    }
    _loaded = stored != null || migrated != null;
    if (stored != null) {
      if (!_credentialsMarked()) {
        unawaited(_storeMutex.protect(() async {
          if (_sessionChanges == sessions) await _markStored(true);
        }));
      }
      return _parse(stored);
    }
    if (migrated != null) return null;
    return _migrateLegacy(sessions);
  }

  static oauth2.Credentials? _parse(String json) {
    try {
      return oauth2.Credentials.fromJson(json);
    } on FormatException {
      // Its message holds the tokens.
      _logger.w("Stored credentials are not readable");
      return null;
    }
  }

  Future<oauth2.Credentials?> _migrateLegacy(int sessions) async {
    final values = <String, String?>{};
    try {
      await _legacyStorage.invokeMethod<void>('initialize');
      for (final key in const ['ACCESS_TOKEN', 'ID_TOKEN', 'REFRESH_TOKEN', 'EXPIRES_ON']) {
        values[key] = await _legacyStorage.invokeMethod<String>('read', {'key': key});
      }
    } on MissingPluginException {
      // No plugin, so nothing it stored.
    } catch (e) {
      _logger.w("Could not read the previous identity: ${e.runtimeType}");
      return null;
    }
    _loaded = true;
    final accessToken = values['ACCESS_TOKEN'];
    final idToken = values['ID_TOKEN'];
    if (accessToken == null || idToken == null) {
      unawaited(_retireLegacy());
      return null;
    }
    // Without its token endpoint unless a discovery has run: the first
    // refresh discovers it, and the migration does not wait for the network.
    final credentials = oauth2.Credentials(
      accessToken,
      refreshToken: values['REFRESH_TOKEN'],
      idToken: idToken,
      tokenEndpoint: _discoveries[discoveryUrl]?.tokenEndpoint,
      expiration: DateTime.fromMillisecondsSinceEpoch(
          int.tryParse(values['EXPIRES_ON'] ?? '') ?? 0),
    );
    // The previous values go only once the new ones are stored; until then
    // the next start moves them again.
    if (await _store(credentials, sessions)) unawaited(_retireLegacy());
    return credentials;
  }

  /// Marks the previous identity as moved, then deletes it. Best effort:
  /// once marked it is never read again.
  Future<void> _retireLegacy() async {
    try {
      await _storage.write(key: _legacyMigratedKey, value: '1');
    } catch (e) {
      _logger.w("Could not mark the previous identity as moved: ${e.runtimeType}");
    }
    try {
      await _legacyStorage.invokeMethod<void>('initialize');
      for (final key in _legacyKeys) {
        await _legacyStorage.invokeMethod<void>('delete', {'key': key});
      }
    } on MissingPluginException {
      // Nothing stored there.
    } catch (e) {
      _logger.w("Could not delete the previous identity: ${e.runtimeType}");
    }
    try {
      await _storage.delete(key: encKeyName);
    } catch (e) {
      _logger.w("Could not delete the previous encryption key: ${e.runtimeType}");
    }
  }

  /// Stores [credentials] unless the session changed since [sessions].
  Future<bool> _store(oauth2.Credentials credentials, int sessions) =>
      _storeMutex.protect(() async {
        if (_sessionChanges != sessions) return false;
        try {
          await _storage.write(key: _credentialsKey, value: credentials.toJson());
        } catch (e) {
          _logger.w("Could not store the credentials: ${e.runtimeType}");
          return false;
        }
        await _markStored(true);
        return true;
      });

  /// Deletes the stored and the previous credentials, unless the session
  /// changed since [sessions] when given.
  Future<void> _deleteStored([int? sessions]) async {
    var deleting = true;
    await _storeMutex.protect(() async {
      if (sessions != null && _sessionChanges != sessions) {
        deleting = false;
        return;
      }
      try {
        await _storage.delete(key: _credentialsKey);
      } catch (e) {
        _logger.w("Could not delete the stored credentials: ${e.runtimeType}");
        return;
      }
      await _markStored(false);
    });
    if (deleting) await _retireLegacy();
  }

  /// Whether credentials were stored and not deleted since, as recorded in
  /// [Settings]; false when that cannot be read.
  static bool _credentialsMarked() {
    try {
      return Settings.getCredentialsStored();
    } catch (_) {
      return false;
    }
  }

  /// [Settings.getSignedOut]; false when that cannot be read.
  static bool _signedOutMarked() {
    try {
      return Settings.getSignedOut();
    } catch (_) {
      return false;
    }
  }

  static Future<void> _markSignedOut(bool signedOut) async {
    try {
      await Settings.setSignedOut(signedOut);
    } catch (e) {
      _logger.w("Could not record whether the account signed out: ${e.runtimeType}");
    }
  }

  static Future<void> _markStored(bool stored) async {
    try {
      await Settings.setCredentialsStored(stored);
    } catch (e) {
      _logger.w("Could not record whether credentials are stored: ${e.runtimeType}");
    }
  }

  /// The discovery document of the current URL, fetched at most once at a
  /// time. [retryNow] false leaves it alone within [setupRetryInterval] of a
  /// failed one. [bound] limits the wait, not the request.
  Future<_Discovery?> _discover(
      {required bool retryNow, required Duration bound}) async {
    final url = discoveryUrl;
    final known = _discoveries[url];
    if (known != null) return known;
    final failedAt = _discoveryFailedAt;
    if (!retryNow &&
        failedAt != null &&
        monotonicNow() - failedAt < setupRetryInterval) {
      return null;
    }
    final epoch = ApiAvailableService.reachabilityEpoch;
    // A request can hang for good, so only a recent one for this URL is
    // joined.
    final running = _runningDiscovery;
    final discovery = running != null &&
            running.url == url &&
            monotonicNow() - running.startedAt < loginTimeout
        ? running
        : _startDiscovery(url);
    try {
      final result = await discovery.result.timeout(bound);
      _discoveryFailedAt = null;
      // The auth server answered, so an outage mark may be stale; checked
      // before the session's first requests would be refused for it.
      if (ApiAvailableService.isPlatformUnreachable) {
        await ApiAvailableService().recheckPlatform();
      }
      return result;
    } catch (e) {
      _logger.d("Discovery failed: ${_describe(e)}");
      _discoveryFailedAt = monotonicNow();
      _noteUnanswered(e, epoch);
      return null;
    }
  }

  _RunningDiscovery _startDiscovery(String url) {
    final running = _RunningDiscovery(_fetchDiscovery(url), url, monotonicNow());
    _runningDiscovery = running;
    unawaited(running.result
        .then<void>((d) => _discoveries[url] = d, onError: (Object _) {})
        .whenComplete(() {
      if (identical(_runningDiscovery, running)) _runningDiscovery = null;
    }));
    return running;
  }

  static Future<_Discovery> _fetchDiscovery(String url) async {
    final client = httpClient();
    try {
      final response = await client.get(Uri.parse(url));
      if (response.statusCode != 200) {
        throw FormatException("Discovery answered ${response.statusCode}");
      }
      final document = jsonDecode(response.body);
      final token = document is Map ? document['token_endpoint'] : null;
      if (token is! String) throw const FormatException("No token endpoint");
      final revocation = (document as Map)['revocation_endpoint'];
      final device = document['device_authorization_endpoint'];
      return _Discovery(
          Uri.parse(token),
          revocation is String ? Uri.parse(revocation) : null,
          device is String ? _httpUri(device) : null);
    } finally {
      client.close();
    }
  }

  /// A slow or failing auth server alone is no outage; a transport error is,
  /// and a timeout or a broken connection once a probe fails as well.
  static void _noteUnanswered(Object e, int epoch) {
    if (e is TimeoutException || e is HttpException) {
      unawaited(ApiAvailableService().confirmUnreachable(observedAt: epoch));
    } else if (e is IOException) {
      ApiAvailableService().markPlatformUnreachable(observedAt: epoch);
    } else if (e is http.ClientException) {
      unawaited(ApiAvailableService().confirmUnreachable(observedAt: epoch));
    }
  }

  /// Never the message: oauth2 puts the response body into its exceptions,
  /// and that can hold tokens.
  static String _describe(Object e) => e is oauth2.AuthorizationException
      ? "${e.runtimeType}(${e.error})"
      : "${e.runtimeType}";

  /// Refreshes [from], bounded by [bound] or [tokenRefreshTimeout]. A refresh
  /// that runs into the bound goes on; [_settleRefresh] takes its result.
  Future<bool> _refreshBounded(oauth2.Credentials from, Duration? bound) async {
    final refresh = _joinableRefresh(from) ?? await _startRefresh(from, bound);
    if (refresh == null) return tokenValid;
    final limit = bound ?? tokenRefreshTimeout;
    var timedOut = false;
    await refresh.request
        .then((_) {}, onError: (Object _) {})
        .timeout(limit, onTimeout: () {
      timedOut = true;
    });
    if (timedOut) {
      unawaited(
          ApiAvailableService().confirmUnreachable(observedAt: refresh.epoch));
      return false;
    }
    await refresh.settled;
    return tokenValid;
  }

  Future<_Refresh?> _startRefresh(oauth2.Credentials from, Duration? bound) async {
    var request = from;
    if (from.tokenEndpoint == null) {
      final discovery = await _discover(
          retryNow: bound != null, bound: bound ?? clientSetupTimeout);
      if (discovery == null || !identical(_credentials, from)) return null;
      final running = _joinableRefresh(from);
      if (running != null) return running;
      request = oauth2.Credentials(from.accessToken,
          refreshToken: from.refreshToken,
          idToken: from.idToken,
          tokenEndpoint: discovery.tokenEndpoint,
          scopes: from.scopes,
          expiration: from.expiration);
    }
    final refresh = _Refresh(from, _sessionChanges,
        ApiAvailableService.reachabilityEpoch, monotonicNow(),
        _requestRefresh(request));
    _refreshing = refresh;
    refresh.settled = _settleRefresh(refresh);
    return refresh;
  }

  /// The running refresh of [from], unless it is older than [loginTimeout]:
  /// a request can hang for good, and then a new one goes out.
  _Refresh? _joinableRefresh(oauth2.Credentials from) {
    final running = _refreshing;
    return running != null &&
            identical(running.from, from) &&
            monotonicNow() - running.startedAt < loginTimeout
        ? running
        : null;
  }

  static Future<oauth2.Credentials> _requestRefresh(
      oauth2.Credentials credentials) async {
    final client = httpClient();
    try {
      return await credentials.refresh(
          identifier: _clientId,
          newScopes: _scopes,
          basicAuth: false,
          httpClient: client);
    } finally {
      client.close();
    }
  }

  /// Applies the outcome of [refresh] once it ends, also late, unless a login
  /// or logout came between or another refresh replaced its credentials.
  /// Only `invalid_grant` ends the session; any other failure keeps it. A
  /// refresh replaced by a newer one of the same credentials neither
  /// overrides a result of that one nor logs out while it runs.
  Future<void> _settleRefresh(_Refresh refresh) async {
    oauth2.Credentials? refreshed;
    Object? error;
    try {
      refreshed = await refresh.request;
    } catch (e) {
      error = e;
    }
    if (identical(_refreshing, refresh)) _refreshing = null;
    if (_sessionChanges != refresh.sessions ||
        !identical(_credentials, refresh.from)) {
      _logger.d("Dropped a refresh that ended after its session");
      return;
    }
    if (refreshed != null) {
      // Kept also when its caller gave up: the server may have rotated the
      // refresh token, which leaves the previous one invalid.
      _credentials = refreshed;
      await _store(refreshed, refresh.sessions);
      if (_sessionChanges != refresh.sessions) return;
      notifyListeners();
      // Not awaited, nor is the cleanup below: both take the lock of
      // ClientCertificates, whose holder may be waiting on this refresh.
      unawaited(_rememberAccountOf(refreshed, refresh.sessions));
      return;
    }
    _logger.w("Token refresh failed: ${_describe(error!)}");
    if (error is oauth2.AuthorizationException && error.error == 'invalid_grant') {
      // A newer request sent the same refresh token; its outcome decides.
      final newer = _refreshing;
      if (newer != null && identical(newer.from, refresh.from)) return;
      unawaited(_cleanup());
    } else {
      _noteUnanswered(error, refresh.epoch);
    }
  }

  /// The password grant, bounded by [loginTimeout]. A grant that answers
  /// after it starts no session.
  Future<oauth2.Credentials> _grantBounded(
      Uri tokenEndpoint, String user, String pw) async {
    final pending = _requestGrant(tokenEndpoint, user, pw);
    try {
      return await pending.timeout(loginTimeout);
    } on TimeoutException {
      unawaited(pending.then((_) {},
          onError: (Object e) => _logger.d("Late login failed: ${_describe(e)}")));
      throw AuthException("Can't login, are you online?");
    } on oauth2.AuthorizationException catch (e) {
      _logger.w("Login refused: ${_describe(e)}");
      if (e.error == 'invalid_grant' &&
          (e.description?.contains(invalidCredentials) ?? false)) {
        throw AuthException(invalidCredentials);
      }
      throw AuthException(e.description ?? e.error);
    } on IOException {
      throw AuthException("Can't login, are you online?");
    } on http.ClientException {
      throw AuthException("Can't login, are you online?");
    } on FormatException {
      // Its message holds the response body.
      throw AuthException("Unexpected answer from the auth server");
    }
  }

  static Future<oauth2.Credentials> _requestGrant(
      Uri tokenEndpoint, String user, String pw) async {
    final client = httpClient();
    try {
      final granted = await oauth2.resourceOwnerPasswordGrant(
          tokenEndpoint, user, pw,
          identifier: _clientId,
          scopes: _scopes,
          // A public client: client_id in the body, no secret. The default
          // basic auth would require one.
          basicAuth: false,
          httpClient: client);
      return granted.credentials;
    } finally {
      client.close();
    }
  }

  /// The claims of the ID token, or of the access token without one. Not
  /// verified: they only name the account.
  static Map<String, dynamic> _claimsOf(oauth2.Credentials credentials) {
    final claims = _decodeClaims(credentials.idToken);
    return claims.isNotEmpty ? claims : _decodeClaims(credentials.accessToken);
  }

  static Map<String, dynamic> _decodeClaims(String? jwt) {
    final parts = jwt?.split('.');
    if (parts == null || parts.length != 3) return const {};
    try {
      final payload =
          jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      return payload is Map<String, dynamic> ? payload : const {};
    } catch (_) {
      return const {};
    }
  }

  static String? _subjectOf(oauth2.Credentials credentials) {
    final sub = _claimsOf(credentials)['sub']?.toString();
    return sub == null || sub.isEmpty ? null : sub;
  }

  // Written before loggedIn flips, because the tabs mount on that flag and read
  // the per-account favorites right away. Never cleared on logout: the
  // favorites are keyed by it and have to survive until that account returns.
  //
  // This is also the one place that sees an account actually change, which is
  // what the cache wipe below hangs on.
  Future<void> _rememberAccount(String? sub) async {
    if (sub == null) return;
    var unchanged = false;
    try {
      await _accountMutex.protect(() async {
        final previous = Settings.getAccount();
        if (previous == null || previous == sub) {
          await Settings.setAccount(sub);
          unchanged = true;
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
        await CacheHelper.switchAccount(sub);
        _logger.d("Account changed, dropped the previous account's cache");
      });
    } catch (e) {
      // Never let this escape: init() runs it on the path that decides whether
      // the app gets past the login spinner at all.
      _logger.w("Could not switch account cleanly: $e");
    }
    // A switch whose wipe did not complete; the rows of this account it drops
    // too are refilled by the next refresh. Not awaited: the wipe takes the
    // lock of ClientCertificates, whose holder may be waiting on this sign-in.
    if (unchanged) _wipeRetry = _retryPendingWipe();
  }

  static Future<void> _retryPendingWipe() async {
    try {
      await CacheHelper.retryPendingAccountWipe();
    } catch (e, s) {
      ErrorReporter.log("Could not retry the account wipe", e, s);
    }
  }

  /// [_rememberAccount] for refreshed credentials, unless the session
  /// changed since [sessions].
  Future<void> _rememberAccountOf(oauth2.Credentials credentials, int sessions) async {
    if (_sessionChanges != sessions) return;
    await _rememberAccount(_subjectOf(credentials));
  }

  Future<void> login(String user, String pw) async {
    cancelCodeLogin();
    await _m.protect(() async {
      // loggingIn (== mutex held) just became true; without this notify the
      // login form stays frozen with no feedback until the grant completes.
      notifyListeners();
      await _ensureLoaded();
      if (tokenValid) {
        _logger.d("Old token still valid");
        return;
      }
      // Before the refresh, which then finds the token endpoint of
      // credentials moved without it: the login waits for it only once.
      final discovery = await _discover(retryNow: true, bound: loginTimeout);
      if (discovery == null) {
        throw AuthException("Can't login, are you online?");
      }
      if (await __refresh(bound: loginTimeout)) {
        _logger.d("refreshed token");
        return;
      }
      final credentials =
          await _grantBounded(discovery.tokenEndpoint, user, pw);
      final sub = _subjectOf(credentials);
      if (sub == null) {
        _logger.w("Granted tokens name no account");
        throw AuthException("token null");
      }
      await _startSession(credentials, sub);
    });
  }

  /// Starts the session of [credentials] granted to [sub], for every kind of
  /// login. The caller holds [_m].
  Future<void> _startSession(oauth2.Credentials credentials, String sub) async {
    // A cleanup still running, also of a refresh refused before, would clear
    // this session's state.
    await _awaitCleanup();
    _logger.i('Logged in');
    _signedOut = false;
    _loaded = true;
    _readFailed = false;
    final sessions = ++_sessionChanges;
    _credentials = credentials;
    // Only once stored: until then the next start takes no credentials.
    if (await _store(credentials, sessions) && _sessionChanges == sessions) {
      await _markSignedOut(false);
    }
    unawaited(_retireLegacy());
    await _rememberAccount(sub);
    loggedIn = true;
    notifyListeners();
  }

  /// Signs in with a code the user enters on another device (RFC 8628).
  /// [onCode] gets the code once the server issued it. True once signed in;
  /// false when cancelled, replaced by another sign-in, or when a session
  /// came first. Throws an [AuthException] with the message to show.
  ///
  /// The wait does not hold [_m]: [loggingIn] and [getHeaders] stay free.
  Future<bool> loginWithCode(void Function(DeviceCode code) onCode) async {
    _codeLogin?.cancel();
    final run = _CodeLogin();
    _codeLogin = run;
    try {
      final discovery = await _discover(retryNow: true, bound: loginTimeout);
      if (run.cancelled) return false;
      if (discovery == null) throw AuthException(_offline);
      final endpoint = discovery.deviceAuthorizationEndpoint;
      if (endpoint == null) throw AuthException(codeLoginUnavailable);
      final grant = await _requestDeviceCode(run, endpoint);
      onCode(grant.code);
      final credentials =
          await _pollDeviceCode(run, discovery.tokenEndpoint, grant);
      try {
        return await _m.protect(() async {
          if (run.cancelled) return false;
          // loggingIn is true: the spinner replaces Cancel, which could no
          // longer stop this session.
          notifyListeners();
          await _ensureLoaded();
          if (tokenValid) {
            _logger.d("Dropped the tokens of a code: a session came first");
            return false;
          }
          final sub = _subjectOf(credentials);
          if (sub == null) {
            _logger.w("Granted tokens name no account");
            throw AuthException("token null");
          }
          await _startSession(credentials, sub);
          return true;
        });
      } finally {
        // loggingIn is false again.
        notifyListeners();
      }
    } on _CodeLoginCancelled {
      return false;
    } finally {
      run.cancel();
      if (identical(_codeLogin, run)) _codeLogin = null;
    }
  }

  /// Ends a running [loginWithCode]; a result it gets later starts no session.
  void cancelCodeLogin() {
    _codeLogin?.cancel();
    _codeLogin = null;
  }

  Future<_DeviceGrant> _requestDeviceCode(_CodeLogin run, Uri endpoint) async {
    final sentAt = monotonicNow();
    final response = await _postBounded(run, endpoint,
        {'client_id': _clientId, 'scope': _scopes.join(' ')}, loginTimeout);
    if (response == null) throw AuthException(_offline);
    if (response.statusCode != 200) {
      final error = _oauthErrorOf(response);
      if (error == null) {
        _logger.w("Device authorization answered ${response.statusCode}");
        throw AuthException(_unexpectedAnswer);
      }
      _logger.w("Device authorization refused: ${error.error}");
      if (error.error == 'unauthorized_client') {
        throw AuthException(codeLoginDisabled);
      }
      throw AuthException(error.description ?? error.error);
    }
    final grant = _parseDeviceGrant(response.body, sentAt);
    if (grant == null) {
      _logger.w("Device authorization answered an unreadable code");
      throw AuthException(_unexpectedAnswer);
    }
    return grant;
  }

  /// The parts of a device authorization answer, or null when one is missing
  /// or malformed. The lifetime counts from [sentAt], before the server's.
  static _DeviceGrant? _parseDeviceGrant(String body, Duration sentAt) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (json is! Map) return null;
    final deviceCode = json['device_code'];
    final userCode = json['user_code'];
    final uri = json['verification_uri'];
    final complete = json['verification_uri_complete'];
    final expiresIn = _seconds(json['expires_in']);
    final interval = json['interval'] == null ? 5 : _seconds(json['interval']);
    if (deviceCode is! String ||
        deviceCode.isEmpty ||
        userCode is! String ||
        userCode.trim().isEmpty ||
        uri is! String ||
        expiresIn == null ||
        expiresIn <= 0 ||
        interval == null) {
      return null;
    }
    final verificationUri = _httpUri(uri);
    if (verificationUri == null) return null;
    final lifetime = deviceSecond * _capSeconds(expiresIn);
    return _DeviceGrant(
        deviceCode,
        DeviceCode._(userCode.trim(), verificationUri,
            complete is String ? _httpUri(complete) : null, sentAt + lifetime),
        // At least a second, so that a server sending 0 is not polled in a
        // loop.
        deviceSecond * _capSeconds(interval < 1 ? 1 : interval));
  }

  /// A whole number of seconds as JSON may carry it, or null.
  static int? _seconds(Object? value) {
    if (value is int) return value;
    if (value is double && value.isFinite && value == value.truncateToDouble()) {
      return value.clamp(-_maxDeviceSeconds, _maxDeviceSeconds).toInt();
    }
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static int _capSeconds(int seconds) =>
      seconds > _maxDeviceSeconds ? _maxDeviceSeconds : seconds;

  /// [value] as an absolute http(s) address, or null.
  static Uri? _httpUri(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return null;
    return uri.scheme == 'https' || uri.scheme == 'http' ? uri : null;
  }

  /// Polls the token endpoint until the user confirmed or declined on the
  /// other device, or the code expired. Transport errors, timeouts and
  /// answers that are no OAuth error are retried at the interval.
  Future<oauth2.Credentials> _pollDeviceCode(
      _CodeLogin run, Uri tokenEndpoint, _DeviceGrant grant) async {
    var interval = grant.interval;
    final expiresAt = grant.code._expiresAt;
    while (true) {
      final left = expiresAt - monotonicNow();
      if (left <= Duration.zero) throw AuthException(codeExpired);
      await run.sleep(interval < left ? interval : left);
      final remaining = expiresAt - monotonicNow();
      if (remaining <= Duration.zero) throw AuthException(codeExpired);
      // The wall clock, as oauth2 takes it for the expiration it compares.
      final startTime = DateTime.now();
      final response = await _postBounded(
          run,
          tokenEndpoint,
          {
            'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
            'device_code': grant.deviceCode,
            'client_id': _clientId,
          },
          remaining < loginTimeout ? remaining : loginTimeout);
      if (response == null) continue;
      if (response.statusCode == 200) {
        final credentials =
            _parseTokens(response.body, tokenEndpoint, startTime);
        if (credentials == null) {
          _logger.w("Code login answered unreadable tokens");
          throw AuthException(_unexpectedAnswer);
        }
        return credentials;
      }
      final error = _oauthErrorOf(response);
      switch (error?.error) {
        case null:
          _logger.d("Code poll answered ${response.statusCode}");
        case 'authorization_pending':
          break;
        case 'slow_down':
          interval += deviceSecond * 5;
        case 'access_denied':
          throw AuthException(codeLoginDeclined);
        case 'expired_token':
          throw AuthException(codeExpired);
        case 'unauthorized_client':
          throw AuthException(codeLoginDisabled);
        default:
          _logger.w("Code login refused: ${error!.error}");
          throw AuthException(error.description ?? error.error);
      }
    }
  }

  /// Posts [form] as a public client. Null on a transport error or past
  /// [bound]; a late answer is dropped, and a cancellation is thrown.
  Future<http.Response?> _postBounded(_CodeLogin run, Uri endpoint,
      Map<String, String> form, Duration bound) async {
    final client = httpClient();
    try {
      return await run.bounded(client.post(endpoint, body: form), bound);
    } on TimeoutException {
      _logger.d("Code login request ran into its bound");
      return null;
    } on IOException catch (e) {
      _logger.d("Code login request failed: ${e.runtimeType}");
      return null;
    } on http.ClientException catch (e) {
      _logger.d("Code login request failed: ${e.runtimeType}");
      return null;
    } finally {
      // Aborts a request still running.
      client.close();
    }
  }

  /// The OAuth error of a 4xx answer, or null for any other answer.
  static ({String error, String? description})? _oauthErrorOf(
      http.Response response) {
    if (response.statusCode < 400 || response.statusCode >= 500) return null;
    try {
      final json = jsonDecode(response.body);
      if (json is! Map) return null;
      final error = json['error'];
      final description = json['error_description'];
      if (error is! String || error.isEmpty) return null;
      return (
        error: error,
        description: description is String ? description : null
      );
    } on FormatException {
      return null;
    }
  }

  /// A token answer as oauth2's own grants read it, which it does not
  /// export; null when malformed. Never logs the body, which holds tokens.
  static oauth2.Credentials? _parseTokens(
      String body, Uri tokenEndpoint, DateTime startTime) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (json is! Map) return null;
    final accessToken = json['access_token'];
    final tokenType = json['token_type'];
    if (accessToken is! String || accessToken.isEmpty) return null;
    if (tokenType is! String || tokenType.toLowerCase() != 'bearer') return null;
    for (final name in const ['refresh_token', 'id_token', 'scope']) {
      if (json[name] != null && json[name] is! String) return null;
    }
    DateTime? expiration;
    if (json['expires_in'] != null) {
      final expiresIn = _seconds(json['expires_in']);
      if (expiresIn == null) return null;
      // The grace oauth2 takes, so the token counts as expired a little
      // before the server's view.
      expiration = startTime.add(
          Duration(seconds: _capSeconds(expiresIn)) - const Duration(seconds: 10));
    }
    final scope = json['scope'] as String?;
    return oauth2.Credentials(accessToken,
        refreshToken: json['refresh_token'] as String?,
        idToken: json['id_token'] as String?,
        tokenEndpoint: tokenEndpoint,
        scopes: scope?.split(' ') ?? _scopes,
        expiration: expiration);
  }

  Future<void> logout(BuildContext context) async {
    await _ensureLoaded();
    if (!loggedIn) return;
    final credentials = _credentials;
    if (credentials == null || ApiAvailableService.isPlatformUnreachable) {
      // Without revoking: there is no readable token, or the revocation could
      // only run into its bound. Not in local mode, which leaves the auth
      // server reachable.
      await _cleanup();
    } else {
      await _revokeAndLogOut(credentials);
    }
    if (!context.mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _revokeAndLogOut(oauth2.Credentials credentials) async {
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
    final sessions = _sessionChanges;
    try {
      final reached = await _revoke(credentials)
          .timeout(logoutTimeout, onTimeout: () => false);
      if (!reached) _logger.w("Token not revoked: the auth server did not answer");
    } catch (e) {
      _logger.w("Token revocation failed: ${_describe(e)}");
    }
    _logger.d("logout");
    // A login while the revocation ran keeps its session.
    if (_sessionChanges != sessions) return;
    await _cleanup();
  }

  /// Revokes the refresh token; false when the auth server could not be
  /// discovered, as when it does not answer.
  Future<bool> _revoke(oauth2.Credentials credentials) async {
    final token = credentials.refreshToken;
    if (token == null) return true;
    final discovery = await _discover(retryNow: true, bound: logoutTimeout);
    if (discovery == null) return false;
    final endpoint = discovery.revocationEndpoint;
    if (endpoint == null) return true;
    final client = httpClient();
    try {
      final response = await client.post(endpoint, body: {
        'token': token,
        'token_type_hint': 'refresh_token',
        'client_id': _clientId,
      });
      if (response.statusCode != 200) {
        throw HttpException("Revocation answered ${response.statusCode}");
      }
      return true;
    } finally {
      client.close();
    }
  }

  /// Ends the session in memory, so nothing uses it while the cleanup runs.
  void _endSession() {
    _sessionChanges++;
    _signedOut = true;
    _credentials = null;
    _refreshing = null;
    loggedIn = false;
    notifyListeners();
  }

  /// Runs [steps] as the current cleanup; a failure in them is logged.
  Future<void> _runCleanup(Future<void> Function() steps) {
    final running = () async {
      try {
        await steps();
      } catch (e, s) {
        ErrorReporter.log("Logout cleanup failed", e, s);
      }
    }();
    _cleaning = running;
    return running;
  }

  /// Waits at most [loginTimeout]; a cleanup that ran on past it could still
  /// clear the next session's state, so the login fails instead.
  Future<void> _awaitCleanup() async {
    Future<void> drain() async {
      for (var running = _cleaning; running != null; running = _cleaning) {
        await running;
        if (identical(_cleaning, running)) _cleaning = null;
      }
    }

    try {
      await drain().timeout(loginTimeout);
    } on TimeoutException {
      _logger.w("The cleanup of the last logout has not ended");
      throw AuthException("Can't login, are you online?");
    }
  }

  /// Runs the logout cleanup without a signed-in session.
  @visibleForTesting
  Future<void> cleanupForTest() => _cleanup();

  /// Replaces the server check of the refresh.
  @visibleForTesting
  static Future<bool> Function()? serverAvailableOverride;

  /// Runs the logout without the revocation, as offline or after a refresh
  /// Keycloak refused.
  @visibleForTesting
  Future<void> onLogoutForTest() => _cleanup();

  /// Records the account [sub] as signed in, as every sign-in path does
  /// before [loggedIn] flips, and waits for the wipe retry that follows.
  @visibleForTesting
  Future<void> rememberAccountForTest(String sub) async {
    await _rememberAccount(sub);
    await _wipeRetry;
  }

  /// Forgets the session in memory, the discovery and a failed one, without
  /// logging out; what runs on from before is dropped when it ends.
  @visibleForTesting
  Future<void> resetForTest() async {
    cancelCodeLogin();
    _sessionChanges++;
    _credentials = null;
    _refreshing = null;
    _cleaning = null;
    _runningDiscovery = null;
    _discoveries.clear();
    _discoveryFailedAt = null;
    _signedOut = false;
    _loaded = false;
    _readFailed = false;
    loggedIn = false;
    isInitialized = false;
  }

  /// Every logout, with or without the revocation before it: no step needs
  /// the network. Signed out at once, before the cleanup.
  Future<void> _cleanup() {
    _endSession();
    return _runCleanup(_clearSessionData);
  }

  /// What a session leaves beyond [_endSession]. The stored credentials go
  /// first, and each later step runs whatever the others do.
  Future<void> _clearSessionData() async {
    _logged("Could not reset the live values", () {
      AccountEpoch.advance();
      LiveValues.instance.accountChanged();
    });
    // Before the deletion, which may fail or report success without deleting.
    await _markSignedOut(true);
    await _deleteStored();
    // The live client certificate logs into the broker as this user until it
    // expires; it must not outlive the session.
    await _loggedAsync("Could not delete the live client certificate", () async {
      final account = Settings.getAccount();
      if (account != null) await ClientCertificates.forget(account);
    });
    await _loggedAsync("Could not clear the cache", CacheHelper.clearCache);
    await _loggedAsync("Could not reset the app state", AppState().onLogout);
  }

  static void _logged(String message, void Function() step) {
    try {
      step();
    } catch (e, s) {
      ErrorReporter.log(message, e, s);
    }
  }

  static Future<void> _loggedAsync(
      String message, Future<void> Function() step) async {
    try {
      await step();
    } catch (e, s) {
      ErrorReporter.log(message, e, s);
    }
  }

  Future<Map<String, String>> getHeaders() async {
    if (headersOverride != null) return headersOverride!();
    if (!loggedIn && _readFailed) await _ensureLoaded();
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
    final token = await getToken();
    if (token.isEmpty) return {};
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
    await _ensureLoaded();
    if (tokenValid) return true;
    final credentials = _credentials;
    if (loggedIn &&
        credentials != null &&
        credentials.refreshToken != null &&
        (await _serverAvailable())) {
      return _refreshBounded(credentials, bound);
    }
    return false;
  }

  bool get tokenValid => loggedIn && (_credentials == null || !_credentials!.isExpired); //assumed logged in when offline

  bool get loggingIn => _m.isLocked;

  Future<String> getToken() async {
    final credentials = _credentials;
    if (credentials != null) return credentials.accessToken;
    try {
      final stored = await _storage.read(key: _credentialsKey);
      if (stored != null) return _parse(stored)?.accessToken ?? "";
    } catch (e) {
      _logger.w("Could not read the stored credentials: ${e.runtimeType}");
    }
    return "";
  }

  String? getUsername() {
    final credentials = _credentials;
    if (credentials == null) return null;
    final claims = _claimsOf(credentials);
    return (claims["username"] ?? claims["preferred_username"] ?? claims["sub"])
        ?.toString();
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

/// The endpoints of a discovery document.
class _Discovery {
  _Discovery(this.tokenEndpoint, this.revocationEndpoint,
      this.deviceAuthorizationEndpoint);

  final Uri tokenEndpoint;
  final Uri? revocationEndpoint;

  /// Null when the server offers no sign-in with a code.
  final Uri? deviceAuthorizationEndpoint;
}

/// The code of a sign-in on another device, as the app shows it.
class DeviceCode {
  DeviceCode._(this.userCode, this.verificationUri, this.verificationUriComplete,
      this._expiresAt);

  /// What the user enters on the other device.
  final String userCode;

  /// Where the user enters it.
  final Uri verificationUri;

  /// [verificationUri] with the code filled in, when the server gives one.
  final Uri? verificationUriComplete;

  /// [Auth.monotonicNow] when the code expires.
  final Duration _expiresAt;

  /// The address to share: the one with the code in it when there is one.
  Uri get shareUri => verificationUriComplete ?? verificationUri;

  /// The time left until the code expires, never negative.
  Duration get remaining {
    final left = _expiresAt - Auth.monotonicNow();
    return left.isNegative ? Duration.zero : left;
  }
}

/// A device authorization: the code shown and what the polling needs.
class _DeviceGrant {
  _DeviceGrant(this.deviceCode, this.code, this.interval);

  /// Never shown or logged: it redeems the sign-in.
  final String deviceCode;
  final DeviceCode code;
  final Duration interval;
}

/// Thrown into a sign-in with a code that was cancelled.
class _CodeLoginCancelled implements Exception {
  const _CodeLoginCancelled();
}

/// One sign-in with a code. Its waits end at once when it is cancelled and
/// leave no timer behind.
class _CodeLogin {
  bool cancelled = false;

  /// Ends the wait that runs.
  void Function()? _interrupt;

  void cancel() {
    cancelled = true;
    final interrupt = _interrupt;
    _interrupt = null;
    interrupt?.call();
  }

  /// Waits [duration]; throws [_CodeLoginCancelled] once cancelled.
  Future<void> sleep(Duration duration) => _race<void>(duration, () {});

  /// [request]'s outcome, a [TimeoutException] past [bound], or
  /// [_CodeLoginCancelled] once cancelled. A late outcome is dropped.
  Future<T> bounded<T>(Future<T> request, Duration bound) => _race<T>(
      bound, () => throw TimeoutException("Code login request", bound), request);

  Future<T> _race<T>(Duration limit, T Function() atLimit,
      [Future<T>? request]) {
    if (cancelled) return Future.error(const _CodeLoginCancelled());
    final outcome = Completer<T>();
    late final Timer timer;
    late final void Function() interrupt;
    void settle(void Function() complete) {
      if (outcome.isCompleted) return;
      timer.cancel();
      if (identical(_interrupt, interrupt)) _interrupt = null;
      complete();
    }

    timer = Timer(limit, () => settle(() {
          try {
            outcome.complete(atLimit());
          } catch (e, s) {
            outcome.completeError(e, s);
          }
        }));
    interrupt =
        () => settle(() => outcome.completeError(const _CodeLoginCancelled()));
    _interrupt = interrupt;
    request?.then((value) => settle(() => outcome.complete(value)),
        onError: (Object e, StackTrace s) =>
            settle(() => outcome.completeError(e, s)));
    return outcome.future;
  }
}

/// A discovery request and when it started.
class _RunningDiscovery {
  _RunningDiscovery(this.result, this.url, this.startedAt);

  final Future<_Discovery> result;

  /// The discovery URL it was started with.
  final String url;

  /// [Auth.monotonicNow] when it started.
  final Duration startedAt;
}

/// A refresh request and the session it started in.
class _Refresh {
  _Refresh(this.from, this.sessions, this.epoch, this.startedAt, this.request);

  /// The session's credentials it refreshes.
  final oauth2.Credentials from;

  /// [Auth._sessionChanges] when it started.
  final int sessions;

  /// [ApiAvailableService.reachabilityEpoch] when it started.
  final int epoch;

  /// [Auth.monotonicNow] when it started.
  final Duration startedAt;

  final Future<oauth2.Credentials> request;

  /// Completes once [Auth._settleRefresh] has applied the outcome.
  late final Future<void> settled;
}
