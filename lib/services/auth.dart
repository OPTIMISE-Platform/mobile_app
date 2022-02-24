import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:openid_client/openid_client_io.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:logger/logger.dart';
import 'package:http/http.dart' as http;


const storageKeyUserInfo =  "auth/userinfo";
const storageKeyToken =  "auth/token";
const storageKeyCredential =  "auth/credential";

class Auth {
  static bool _initialized = false;
  static late Issuer _issuer;
  static late Client _client;
  static final _logger = Logger(printer: SimplePrinter(),);
  static const _storage = FlutterSecureStorage();

  static Credential? c;
  static TokenResponse? token;
  static UserInfo? userinfo;
  static http.Client? httpClient;

  static Future<void> init() async {
    if (_initialized) {
      return;
    }
    _issuer = await Issuer.discover(Uri.https(dotenv.env['KEYCLOAK_HOST'] ?? 'localhost', '/auth/realms/' + (dotenv.env['KEYCLOAK_REALM'] ?? 'master')));
    _client = Client(_issuer, dotenv.env['KEYCLOAK_CLIENTID'] ?? 'optimise_mobile_app');

    String? saved = await _storage.read(key: storageKeyUserInfo);
    if (saved != null) {
      _logger.d('Using stored userInfo');
      userinfo = UserInfo.fromJson(json.decode(saved));
    }

    saved = await _storage.read(key: storageKeyToken);
    if (saved != null) {
      _logger.d('Using stored token');
      token = TokenResponse.fromJson(json.decode(saved));
    }

    saved = await _storage.read(key: storageKeyCredential);
    if (saved != null) {
      _logger.d('Using stored credential');
      c = Credential.fromJson(json.decode(saved));
    }
    
    _initialized = true;
  }

  static Future<void> login() async {
    if (!_initialized) {
      await init();
    }

    if (token != null && token!.expiresAt != null && token!.expiresAt!.isAfter(DateTime.now())) {
      _logger.d("Old token still valid");
      return;
    }
    // TODO check refresh token usable

    urlLauncher(String url) async {
      if (await canLaunch(url)) {
        await launch(url, forceWebView: true);
      } else {
        throw 'Could not launch $url';
      }
    }

    // create an authenticator
    var authenticator = Authenticator(_client,
        scopes: ['openid'],
        port: 4000, urlLancher: urlLauncher);

    // starts the authentication
    c = await authenticator.authorize();
    _storage.write(key: storageKeyCredential, value: json.encode(c));

    // close the webview when finished
    try {
      closeWebView();
    } on UnimplementedError {
      // pass
    }

    token = await c?.getTokenResponse();

    if (token != null) {
      _storage.write(key: storageKeyToken, value: json.encode(token));
    }

    _logger.i(token != null ? 'Logged in' : 'Could not login');
    
    return;
  }

  static logout() async {
    _logger.d("logout");
    final uri = c?.generateLogoutUrl();
    if (uri != null) {
      (await getHttpClient()).get(uri);
    }

    c = null;
    token = null;
    userinfo = null;
    httpClient = null;
    await _storage.delete(key: storageKeyUserInfo);
    await _storage.delete(key: storageKeyCredential);
    await _storage.delete(key: storageKeyToken);
    _initialized = false;
    await login();
  }

  static Future<UserInfo?> getUserInfo() async {
    if (c == null) {
      await login();
    }
    userinfo ??= await c?.getUserInfo();
    
    if (userinfo != null) {
      _storage.write(key: storageKeyUserInfo, value: json.encode(userinfo));
    }
    return userinfo;
  }

  static Future<http.Client> getHttpClient() async {
    if (httpClient != null) {
      return httpClient!;
    }
    if (c == null) {
      await login();
    }
    httpClient = c!.createHttpClient();
    return httpClient!;
  }
}
