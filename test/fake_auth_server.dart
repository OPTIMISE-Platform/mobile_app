/*
 * Copyright 2026 InfAI (CC SES)
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
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:oauth2/oauth2.dart' as oauth2;

/// An unsigned JWT carrying [claims]; Auth reads them without verifying.
String jwt(Map<String, Object?> claims) {
  String part(Map<String, Object?> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll("=", "");
  return "${part({"alg": "none"})}.${part(claims)}.sig";
}

final tokenEndpoint = Uri.parse("https://localhost/auth/token");
final revocationEndpoint = Uri.parse("https://localhost/auth/revoke");

/// Credentials of [sub] as a login stores them; [discovered] false leaves out
/// the token endpoint, as the migration does.
oauth2.Credentials credentials(String accessToken,
        {Duration validFor = const Duration(hours: 1),
        String sub = "test-account",
        bool discovered = true}) =>
    oauth2.Credentials(accessToken,
        refreshToken: "refresh-$accessToken",
        idToken: jwt({"sub": sub, "preferred_username": "user-$sub"}),
        tokenEndpoint: discovered ? tokenEndpoint : null,
        expiration: DateTime.now().add(validFor));

/// A token endpoint answer that issues [accessToken] to [sub].
http.Response tokens(String accessToken, {String sub = "test-account"}) =>
    http.Response(
        jsonEncode({
          "access_token": accessToken,
          "token_type": "Bearer",
          "expires_in": 300,
          "refresh_token": "refresh-$accessToken",
          "id_token": jwt({"sub": sub, "preferred_username": "user-$sub"}),
          "scope": "openid offline_access profile email",
        }),
        200,
        headers: {"content-type": "application/json"});

/// An OAuth error answer, as Keycloak sends it.
http.Response oauthError(String error, {String? description, int status = 400}) =>
    http.Response(
        jsonEncode({
          "error": error,
          if (description != null) "error_description": description,
        }),
        status,
        headers: {"content-type": "application/json"});

/// Answers Auth's discovery, token and revocation requests through
/// [Auth.httpClient], and records them.
class FakeAuthServer {
  final requests = <http.Request>[];

  /// Delay the answer until they complete.
  Completer<void>? holdDiscovery;
  Completer<void>? holdToken;
  Completer<void>? holdRevocation;

  /// Thrown instead of an answer.
  Object? discoveryError;
  Object? tokenError;

  int discoveryStatus = 200;
  int revocationStatus = 200;

  /// Answers the token requests; by default a password grant gets
  /// "signed-in" and a refresh "refreshed", both for test-account.
  Future<http.Response> Function(Map<String, String> form)? onToken;

  int get discoveries => requests
      .where((r) => r.url.path.endsWith("/.well-known/openid-configuration"))
      .length;

  List<Map<String, String>> get tokenRequests =>
      [for (final r in requests) if (r.url == tokenEndpoint) r.bodyFields];

  List<http.Request> get tokenHttpRequests =>
      [for (final r in requests) if (r.url == tokenEndpoint) r];

  List<Map<String, String>> get revocations =>
      [for (final r in requests) if (r.url == revocationEndpoint) r.bodyFields];

  void install() => Auth.httpClient = () => MockClient(_handle);

  static void uninstall() => Auth.httpClient = http.Client.new;

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    if (request.url.path.endsWith("/.well-known/openid-configuration")) {
      await holdDiscovery?.future;
      if (discoveryError != null) throw discoveryError!;
      return http.Response(
          jsonEncode({
            "token_endpoint": "$tokenEndpoint",
            "revocation_endpoint": "$revocationEndpoint",
          }),
          discoveryStatus,
          headers: {"content-type": "application/json"});
    }
    if (request.url == tokenEndpoint) {
      await holdToken?.future;
      if (tokenError != null) throw tokenError!;
      final form = request.bodyFields;
      if (onToken != null) return onToken!(form);
      return form["grant_type"] == "password"
          ? tokens("signed-in")
          : tokens("refreshed");
    }
    if (request.url == revocationEndpoint) {
      await holdRevocation?.future;
      return http.Response("", revocationStatus);
    }
    return http.Response("", 404);
  }
}

/// Secure storage whose reads or writes fail on demand. Writes and deletes
/// go to [log], which [LegacyIdentityStore] can share.
class SecureStore extends MapBase<String, String> {
  SecureStore([List<String>? log]) : log = log ?? [];

  final data = <String, String>{};
  final List<String> log;
  bool readFails = false;
  bool writeFails = false;

  /// Answers every read with nothing and no error, as flutter_secure_storage
  /// 9.2.4 on iOS can before the first unlock.
  bool readsNil = false;

  void install() => FlutterSecureStorage.setMockInitialValues(this);

  void put(oauth2.Credentials c) =>
      data[Auth.storageKeys.credentials] = c.toJson();

  oauth2.Credentials? get stored {
    final json = data[Auth.storageKeys.credentials];
    return json == null ? null : oauth2.Credentials.fromJson(json);
  }

  @override
  String? operator [](Object? key) {
    // As the Keychain answers before the first unlock.
    if (readFails) throw PlatformException(code: "-25308");
    if (readsNil) return null;
    return data[key];
  }

  @override
  void operator []=(String key, String value) {
    if (writeFails) throw PlatformException(code: "keystore");
    log.add("write $key");
    data[key] = value;
  }

  @override
  void clear() => data.clear();

  @override
  Iterable<String> get keys => data.keys;

  @override
  String? remove(Object? key) {
    log.add("delete $key");
    return data.remove(key);
  }
}

/// The openidconnect package's storage behind its method channel.
class LegacyIdentityStore {
  LegacyIdentityStore([List<String>? log]) : log = log ?? [];

  static const _channel =
      MethodChannel('plugins.concerti.io/openidconnect_secure_storage');

  final values = <String, String>{};
  final List<String> log;
  bool readFails = false;

  /// An identity of [sub] as the package stored it.
  void put(String accessToken,
      {String sub = "test-account", DateTime? expiresAt}) {
    values
      ..["ACCESS_TOKEN"] = accessToken
      ..["ID_TOKEN"] = jwt({"sub": sub, "preferred_username": "user-$sub"})
      ..["REFRESH_TOKEN"] = "refresh-$accessToken"
      ..["TOKEN_TYPE"] = "bearer"
      ..["EXPIRES_ON"] = "${(expiresAt ?? DateTime.now().add(const Duration(hours: 1))).millisecondsSinceEpoch}";
  }

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      final key = (call.arguments as Map?)?['key'] as String?;
      switch (call.method) {
        case 'read':
          // errSecInteractionNotAllowed, as on a locked iPhone.
          if (readFails) throw PlatformException(code: "-25308");
          return values[key];
        case 'delete':
          log.add("legacy delete $key");
          values.remove(key);
          return null;
        case 'write':
          values[key!] = (call.arguments as Map)['value'] as String;
          return null;
      }
      return null;
    });
  }

  static void uninstall() =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);
}
