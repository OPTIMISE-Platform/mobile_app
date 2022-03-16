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
import 'package:mutex/mutex.dart';
import 'package:openidconnect/openidconnect.dart';

import 'cache_helper.dart';

const storageKeyToken = "auth/token";

class Auth {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );
  static final _m = Mutex();

  static OpenIdConnectClient? _client;

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
        );
      } catch (e) {
        _logger.e("Could not setup client: " + e.toString());
      }
    } else {
      _logger.d("Postponing init(): Currently offline");
    }
    final token = await OpenIdIdentity.load();
    if (token != null) {
      _logger.d("Using token from storage");
      if (!tokenValid()) {
        _logger.d("But token is expired");
      }
    }
  }

  static bool _initialized() {
    return _client != null;
  }

  static Future<void> login(BuildContext context, AppState state) async {
    await _m.acquire();
    if (!_initialized()) {
      await init();
    }

    if (tokenValid()) {
      _logger.d("Old token still valid");
      return;
    }
    if (await _client!.refresh(raiseEvents: false)) {
      _logger.d("refreshed token");
    }
    final OpenIdIdentity? token;
    try {
      token = await _client?.loginInteractive(context: context, title: "Login", popupHeight: 640, popupWidth: 480);
    } catch (e) {
      _logger.e("Login failed: " + e.toString());
      _m.release();
      return;
    }

    if (token != null) {
      token.save();
      _logger.i('Logged in');
    } else {
      _logger.w("_token null");
    }
    _m.release();
    state.notifyListeners();
    return;
  }

  static logout(BuildContext context, AppState state) async {
    if (!_initialized()) {
      await init();
    }
    if (_client?.identity == null) {
      return;
    }

    await _client?.logoutToken();
    await OpenIdIdentity.clear(); // remove saved token

    _logger.d("logout");
    CacheHelper.clearCache();
    state.refreshDevices(context);
    Navigator.of(context).popUntil((route) => route.isFirst);
    state.notifyListeners();
  }

  static Future<Map<String, String>> getHeaders(BuildContext context, AppState state) async {
    if (!tokenValid()) {
      await login(context, state);
    }
    if (!tokenValid()) {
      throw AuthException("login error: token is null");
    }
    return {"Authorization": "Bearer " + _client!.identity!.accessToken};
  }

  static bool tokenValid() {
    return _client?.identity != null && _client!.identity!.expiresAt.isAfter(DateTime.now());
  }

  static bool loggingIn() {
    return _m.isLocked;
  }
}
