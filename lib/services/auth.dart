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

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/exceptions/auth_exception.dart';
import 'package:mobile_app/services/fcm_token.dart';
import 'package:mutex/mutex.dart';
import 'package:openidconnect/openidconnect.dart';
import 'package:http/http.dart' as http;

import '../widgets/toast.dart';
import 'cache_helper.dart';

class Auth extends ChangeNotifier {
  static final _instance = Auth._internal();

  factory Auth() => _instance;

  Auth._internal();

  static final _logger = Logger(
    printer: SimplePrinter(),
  );
  final _m = Mutex();
  final _clientSetupMutex = Mutex();

  static final _httpClient = http.Client();
  OpenIdConnectClient? _client;
  final String _discoveryUrl = (dotenv.env['KEYCLOAK_URL'] ?? 'https://localhost') +
      '/auth/realms/' +
      (dotenv.env['KEYCLOAK_REALM'] ?? 'master') +
      "/.well-known/openid-configuration";

  bool loggedIn = false;

  Future<void> init() async {
    await _clientSetupMutex.protect(() async {
      if (_initialized) {
        return;
      }
      if (await _serverAvailable()) {
        try {
          _client = await OpenIdConnectClient.create(
            discoveryDocumentUrl: _discoveryUrl,
            clientId: dotenv.env['KEYCLOAK_CLIENTID'] ?? 'optimise_mobile_app',
            redirectUrl: kIsWeb
                ? Uri.base.scheme + "://" + Uri.base.host + ":" + Uri.base.port.toString() + "/callback.html"
                : dotenv.env['KEYCLOAK_REDIRECT'] ?? "https://localhost",
            scopes: [OpenIdConnectClient.OFFLINE_ACCESS_SCOPE, ...OpenIdConnectClient.DEFAULT_SCOPES],
            autoRefresh: false,
          );
          loggedIn = _client?.identity != null;
          _client?.changes.listen((event) async {
            _logger.d(event.type.toString() + ": " + event.message.toString());
            switch (event.type) {
              case AuthEventTypes.Refresh:
              case AuthEventTypes.Success:
                loggedIn = true;
                notifyListeners();

                break;
              case AuthEventTypes.NotLoggedIn: // applies if token exists but timed out on client init
                loggedIn = _client?.identity != null;
                if (!loggedIn) {
                  _cleanup();
                }
                notifyListeners();
                break;
              case AuthEventTypes.Error:
              case AuthEventTypes.Logout:
                if (await _serverAvailable()) {
                  loggedIn = false;
                  await _cleanup();
                  notifyListeners();
                } else {
                  _client = null;
                }
            }
          });
        } catch (e) {
          _logger.e("Could not setup client: " + e.toString());
        }
      } else {
        _logger.d("Postponing real init(): Currently offline");
        final token = await OpenIdIdentity.load();
        if (token != null) {
          _logger.d("Using token from storage, assuming still valid");
          loggedIn = true;
          notifyListeners();
        }
      }
    });
  }

  bool get _initialized => _client != null;

  Future<void> login(BuildContext context, String user, String pw) async {
    await _m.protect(() async {
      if (!_initialized) {
        await init();
        if (_client == null) {
          Toast.showErrorToast(context, "Can't login, are you online?");
          return;
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
        _logger.e("Login failed: " + e.toString());
        rethrow;
      }

      if (token != null) {
        _logger.i('Logged in');
        await AppState().initMessaging();
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
      await FcmTokenService.deregisterFcmToken(AppState().fcmToken!);
    }

    _logger.d("logout");
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _cleanup() async {
    await CacheHelper.clearCache();
    await AppState().onLogout();
    await OpenIdIdentity.clear(); // remove saved token
  }

  Future<Map<String, String>> getHeaders() async {
    if (!loggedIn) throw AuthException("Not logged in");
    if (!(await refreshToken())) {
      return {};
    }
    return {"Authorization": "Bearer " + await getToken()};
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
    if (await (Connectivity().checkConnectivity()) == ConnectivityResult.none) {
      return false;
    }
    var uri = Uri.parse(_discoveryUrl);
    if (_discoveryUrl.startsWith("https://")) {
      uri = uri.replace(scheme: "https");
    }
    try {
      final resp = await _httpClient.get(uri);
      return resp.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
