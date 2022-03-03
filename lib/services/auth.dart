import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logger/logger.dart';
import 'package:mutex/mutex.dart';
import 'package:openidconnect/openidconnect.dart';

const storageKeyToken = "auth/token";

class Auth {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );
  static final _m = Mutex();

  static OpenIdConnectClient? _client;
  static OpenIdIdentity? _token;

  static Future<void> init() async {
    if (_initialized()) {
      return;
    }
    ConnectivityResult connectivityResult =
        await (Connectivity().checkConnectivity());

    if (connectivityResult != ConnectivityResult.none) {
      _client = await OpenIdConnectClient.create(
        discoveryDocumentUrl:
            (dotenv.env['KEYCLOAK_URL'] ?? 'https://localhost') +
                '/auth/realms/' +
                (dotenv.env['KEYCLOAK_REALM'] ?? 'master') +
                "/.well-known/openid-configuration",
        clientId: dotenv.env['KEYCLOAK_CLIENTID'] ?? 'optimise_mobile_app',
        redirectUrl: kIsWeb
            ? Uri.base.scheme +
                "://" +
                Uri.base.host +
                ":" +
                Uri.base.port.toString() +
                "/callback.html"
            : dotenv.env['KEYCLOAK_REDIRECT'] ?? "https://localhost",
      );
    } else {
      _logger.d("Postponing init(): Currently offline");
    }
    _token = await OpenIdIdentity.load();
    if (_token != null) {
      _logger.d("Using token from storage");
      if (!tokenValid()) {
        _logger.d("But token is expired");
      }
    }
  }

  static bool _initialized() {
    return _client != null;
  }

  static Future<void> login(BuildContext context) async {
    await _m.acquire();
    if (!_initialized()) {
      await init();
    }

    if (tokenValid()) {
      _logger.d("Old token still valid");
      return;
    }
    try {
      _token = await _client?.loginInteractive(
          context: context,
          title: "Login",
          popupHeight: 640,
          popupWidth: 480);
    } catch (e) {
      _logger.e("Login failed: " + e.toString());
      _m.release();
      return;
    }

    if (_token != null) {
      _token?.save();
      _logger.i('Logged in');
    } else {
      _logger.w("_token null");
    }
    _m.release();
    return;
  }

  static logout(BuildContext context) async {
    if (!_initialized()) {
      await init();
    }
    if (_token == null) {
      return;
    }

    await _client?.logoutToken();
    await OpenIdIdentity.clear(); // remove saved token

    _logger.d("logout");
    _token = null;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  static Future<Map<String, String>> getHeaders(BuildContext context) async {
    if (_token == null) {
      await login(context);
    }
    if (_token == null) {
      throw "login error";
    }
    return {"Authorization": "Bearer " + _token!.accessToken};
  }

  static bool tokenValid() {
    return _token != null &&
        _token!.expiresAt.isAfter(DateTime.now());
  }

  static bool loggingIn() {
    return _m.isLocked;
  }
}
