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
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/exceptions/auth_exception.dart';
import 'package:mobile_app/services/fcm_token.dart';
import 'package:mutex/mutex.dart';
import 'package:openidconnect/openidconnect.dart';

import '../widgets/toast.dart';
import 'cache_helper.dart';

const storageKeyToken = "auth/token";

class Auth {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );
  static final _m = Mutex();

  static OpenIdConnectClient? _client;

  static bool _loggedIn = false;

  static Future<void> init() async {
    if (_initialized()) {
      return;
    }
    ConnectivityResult connectivityResult = await (Connectivity().checkConnectivity());
    if (connectivityResult != ConnectivityResult.none) {
      try {
        _client = await OpenIdConnectClient.create(
          discoveryDocumentUrl: (dotenv.env['KEYCLOAK_URL'] ?? 'https://localhost') +
              '/auth/realms/' +
              (dotenv.env['KEYCLOAK_REALM'] ?? 'master') +
              "/.well-known/openid-configuration",
          clientId: dotenv.env['KEYCLOAK_CLIENTID'] ?? 'optimise_mobile_app',
          redirectUrl: kIsWeb
              ? Uri.base.scheme + "://" + Uri.base.host + ":" + Uri.base.port.toString() + "/callback.html"
              : dotenv.env['KEYCLOAK_REDIRECT'] ?? "https://localhost",
          scopes: [OpenIdConnectClient.OFFLINE_ACCESS_SCOPE, ...OpenIdConnectClient.DEFAULT_SCOPES],
        );
        _client?.changes.listen((event) {
          _logger.d(event.type.toString() + ": " + event.message.toString());
        });
      } catch (e) {
        _logger.e("Could not setup client: " + e.toString());
      }
    } else {
      _logger.d("Postponing init(): Currently offline");
    }
    final token = await OpenIdIdentity.load();
    if (token != null) {
      _loggedIn = true;
      _logger.d("Using token from storage");
      if (_client != null && !tokenValid) {
        _logger.d("But token is invalid");
        if (_client?.hasTokenExpired == true) {
          _logger.d("Token is expired, attempting refresh");
          final ok = await _client?.refresh();
          _logger.d("Refresh was ok? " + ok.toString());
        }
      }
    }
  }

  static bool _initialized() {
    return _client != null;
  }

  static Future<void> login(BuildContext context, AppState state, String user, String pw) async {
    await _m.protect(() async {
      state.notifyListeners();

      if (!_initialized()) {
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
      if (await _client!.refresh(raiseEvents: false)) {
        _logger.d("refreshed token");
      }
      final OpenIdIdentity? token;
      try {
        token = await _client?.loginWithPassword(userName: user, password: pw, prompts: ["none"]);
      } catch (e) {
        _logger.e("Login failed: " + e.toString());
        rethrow;
      }

      if (token != null) {
        token.save();
        _logger.i('Logged in');
        _loggedIn = true;
        await state.initMessaging();
      } else {
        _logger.w("_token null");
        throw AuthException("token null");
      }
      return;
    });
    state.notifyListeners();
  }

  static logout(BuildContext context, AppState state) async {
    if (!_initialized()) {
      await init();
    }
    if (_client?.identity == null) {
      return;
    }

    if (state.fcmToken != null) {
      await FcmTokenService.deregisterFcmToken(state.fcmToken!);
    }
    await CacheHelper.clearCache();
    await state.onLogout();
    await _client?.logoutToken();
    await OpenIdIdentity.clear(); // remove saved token

    _logger.d("logout");
    _loggedIn = false;
    Navigator.of(context).popUntil((route) => route.isFirst);
    state.notifyListeners();
  }

  static Future<Map<String, String>> getHeaders() async {
    if (!tokenValid) {
      throw AuthException("Not logged in");
    }
    return {"Authorization": "Bearer " + await getToken()};
  }

  static Future<bool> refreshToken() async {
    if (tokenValid) return true;
    if (_client != null && _client!.identity != null && _client!.hasTokenExpired == true) {
      final ok = await _client!.refresh();
      return ok && tokenValid;
    }
    return false;
  }

  static bool get tokenValid =>
      _loggedIn && (_client == null || (_client!.identity != null && !_client!.hasTokenExpired)); //assumed logged in when offline

  static bool get loggingIn => _m.isLocked;

  static Future<String> getToken() async {
    if (_client != null) {
      return _client!.identity!.accessToken;
    }
    final token = await OpenIdIdentity.load();
    if (token != null) {
      return token.accessToken;
    }
    return "";
  }

  static String? getUsername() {
    return _client?.identity?.userName;
  }
}
