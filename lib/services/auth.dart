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

import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/exceptions/auth_exception.dart';
import 'package:mobile_app/services/fcm_token.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/dio_factory.dart';
import 'package:mutex/mutex.dart';
import 'package:openidconnect/openidconnect.dart';
import 'package:mobile_app/services/cache_helper.dart';

class Auth extends ChangeNotifier {
  static final _instance = Auth._internal();

  bool isInitialized = false;
  bool _listenerRegistered = false;

  factory Auth() => _instance;

  Auth._internal();

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

  static DateTime? _lastOnlineCheck;
  static const Duration _checkCacheDuration = Duration(seconds: 30);
  static bool _checkCache = false;

  OpenIdConnectClient? _client;
  final String _discoveryUrl =
      "${Settings.getKeycloakUrl() ?? 'https://localhost'}/auth/realms/${dotenv.env['KEYCLOAK_REALM'] ?? 'master'}/.well-known/openid-configuration";

  bool loggedIn = false;

  Future<void> init() async {
    // Trust a stored identity before the client setup: the OIDC discovery in
    // OpenIdConnectClient.create is a network round trip that held the login
    // spinner on every app start. The offline fallback below has always
    // trusted the stored token when the setup fails; trusting it while the
    // setup is still running is the same assumption, just earlier. Backend
    // calls still wait for the real client via getHeaders() -> refreshToken()
    // -> init(), which blocks on the setup mutex.
    if (!isInitialized && !loggedIn) {
      try {
        if (await OpenIdIdentity.load() != null) {
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
      try {
        final start = DateTime.now();
        final encKey = await _getOrCreateEncryptionKey();
        _client = await OpenIdConnectClient.create(
          discoveryDocumentUrl: _discoveryUrl,
          clientId: dotenv.env['KEYCLOAK_CLIENTID'] ?? 'optimise_mobile_app',
          encryptionKey: encKey,
          redirectUrl: kIsWeb
              ? "${Uri.base.scheme}://${Uri.base.host}:${Uri.base.port}/callback.html"
              : Settings.getKeycloakRedirect() ?? "https://localhost",
          scopes: [
            OpenIdConnectClient.OFFLINE_ACCESS_SCOPE,
            ...OpenIdConnectClient.DEFAULT_SCOPES
          ],
          autoRefresh: false,
        );
        _logger.d("OpenIdConnectClient.create ${DateTime.now().difference(start)}");
        loggedIn = _client?.identity != null;
        notifyListeners();
        if (!_listenerRegistered) {
          _listenerRegistered = true;
          _client?.changes.listen((event) async {
            _logger.d("${event.type}: ${event.message}");
            switch (event.type) {
              case AuthEventTypes.Refresh:
              case AuthEventTypes.Success:
                loggedIn = true;
                notifyListeners();
                break;
              case AuthEventTypes.NotLoggedIn:
                loggedIn = _client?.identity != null;
                notifyListeners();
                if (!loggedIn) await _cleanup();
                notifyListeners();
                break;
              case AuthEventTypes.Error:
              case AuthEventTypes.LoggingOut:
                await _onLogout();
            }
          });
        }
      } catch (e) {
        // Offline or server unreachable — fall back to cached token
        _logger.d("Client setup failed (offline?): $e");
        if (!loggedIn) {
          final token = await OpenIdIdentity.load();
          if (token != null) {
            _logger.d("Using token from storage, assuming still valid");
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

  Future<void> login(String user, String pw) async {
    await _m.protect(() async {
      // loggingIn (== mutex held) just became true; without this notify the
      // login form stays frozen with no feedback until the grant completes.
      notifyListeners();
      if (!_initialized) {
        await init();
        if (_client == null) {
          throw AuthException("Can't login, are you online?");
        }
      }

      if (tokenValid) {
        _logger.d("Old token still valid");
        return;
      }
      if (await refreshToken(skipLock: true)) {
        _logger.d("refreshed token");
        return;
      }
      final OpenIdIdentity? token;
      try {
        token = await _client?.loginWithPassword(userName: user, password: pw, prompts: ["none"]);
      } catch (e) {
        _logger.e("Login failed: $e");
        rethrow;
      }

      if (token != null) {
        _logger.i('Logged in');
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
    if (!_initialized) {
      await init();
    }
    if (_client?.identity == null) {
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

    await _client!.logout();
    _logger.d("logout");
    await _onLogout();
    if (!context.mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  _onLogout() async {
    if (await _serverAvailable()) {
      await _cleanup();
    } else {
      _client = null;
    }
    loggedIn = false;
    notifyListeners();
  }

  Future<void> _cleanup() async {
    await CacheHelper.clearCache();
    await AppState().onLogout();
    _listenerRegistered = false;
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
    if (!loggedIn) {
      notifyListeners();
      throw AuthException("Not logged in");
    }
    if (!(await refreshToken())) {
      return {};
    }
    return {"authorization": "Bearer ${await getToken()}", "content-type": Headers.jsonContentType};
  }

  Future<bool> refreshToken({bool skipLock = false}) async {
    if (skipLock) {
      return await __refresh();
    }
    return await _m.protect(__refresh);
  }

  Future<bool> __refresh() async {
    if (!_initialized) {
      await init();
    }
    if (tokenValid) return true;
    if (_client != null && _client!.identity != null && _client!.hasTokenExpired == true && (await _serverAvailable())) {
      final ok = await _client!.refresh();
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
    if (_lastOnlineCheck != null && DateTime.now().difference(_lastOnlineCheck!) < _checkCacheDuration) {
      return _checkCache;
    }
    if (await Connectivity().checkConnectivity() == ConnectivityResult.none) {
      _checkCache = false;
      _lastOnlineCheck = DateTime.now();
      return false;
    }
    try {
      final dio = await DioFactory.create(DioConfig.standard);
      final resp = await dio.get(_discoveryUrl);
      _checkCache = resp.statusCode == 200;
    } catch (e) {
      _checkCache = false;
    } finally {
      _lastOnlineCheck = DateTime.now();
    }
    return _checkCache;
  }
}
