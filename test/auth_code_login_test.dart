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
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_app/exceptions/auth_exception.dart';
import 'package:mobile_app/services/api_available.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/settings.dart';

import 'fake_auth_server.dart';
import 'golden_helper.dart';

const _unit = Duration(milliseconds: 10);

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<T> _within<T>(Future<T> future) =>
    future.timeout(const Duration(seconds: 3));

Matcher _endsWith(String message) => throwsA(
    isA<AuthException>().having((e) => e.message, "message", message));

void main() {
  late FakeAuthServer server;
  late SecureStore store;
  late List<DeviceCode> codes;

  String? storedToken() => store.stored?.accessToken;

  Future<bool> codeLogin() => Auth().loginWithCode(codes.add);

  /// A poll answer the test completes.
  Completer<http.Response> holdPoll() {
    final held = Completer<http.Response>();
    server.codePolls.add(() => held.future);
    return held;
  }

  /// [count] polls answered as still waiting.
  void stillPending(int count) {
    for (var i = 0; i < count; i++) {
      server.codePolls.add(() async => pending());
    }
  }

  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  setUp(() async {
    codes = [];
    server = FakeAuthServer()..install();
    store = SecureStore()..install();
    LegacyIdentityStore().install();
    Auth.serverAvailableOverride = () async => true;
    Auth.deviceSecond = _unit;
    ApiAvailableService.probeOverride = () async => true;
    await Settings.setAccount("test-account");
    await Settings.setCredentialsStored(false);
    await Settings.setSignedOut(false);
  });

  tearDown(() async {
    await pumpEventQueue();
    FakeAuthServer.uninstall();
    LegacyIdentityStore.uninstall();
    Auth.serverAvailableOverride = null;
    Auth.deviceSecond = const Duration(seconds: 1);
    Auth.loginTimeout = const Duration(seconds: 30);
    await Auth().resetForTest();
    ApiAvailableService.resetForTest();
  });

  test("signs in as a password login does, also for the next start", () async {
    stillPending(2);
    server.codePolls.add(() async => tokens("by-code", sub: "account-b"));
    final before = DateTime.now();

    expect(await _within(codeLogin()), isTrue);

    final code = codes.single;
    expect(code.userCode, "ABCD-EFGH");
    expect(code.verificationUri,
        Uri.parse("https://localhost/auth/realms/test/device"));
    expect(code.shareUri,
        Uri.parse("https://localhost/auth/realms/test/device?user_code=ABCD-EFGH"));
    final device = server.deviceRequests.single;
    expect(device.headers.keys.map((k) => k.toLowerCase()),
        isNot(contains("authorization")),
        reason: "a public client, without a secret");
    expect(device.bodyFields, {
      "client_id": dotenv.env["KEYCLOAK_CLIENTID"],
      "scope": "offline_access openid profile email",
    });
    expect(server.polls.map((p) => p.$1), [
      for (var i = 0; i < 3; i++)
        {
          "grant_type": FakeAuthServer.deviceCodeGrant,
          "device_code": "device-1",
          "client_id": dotenv.env["KEYCLOAK_CLIENTID"],
        }
    ]);
    expect(Auth().loggedIn, isTrue);
    expect(storedToken(), "by-code");
    final stored = store.stored!;
    expect(stored.refreshToken, "refresh-by-code");
    expect(stored.tokenEndpoint, tokenEndpoint);
    expect(stored.scopes, ["openid", "offline_access", "profile", "email"]);
    // 300 s from the answer, less oauth2's 10 s grace.
    expect(stored.expiration!.isAfter(before.add(const Duration(seconds: 289))),
        isTrue);
    expect(stored.expiration!.isBefore(DateTime.now().add(const Duration(seconds: 291))),
        isTrue);
    expect(Settings.getAccount(), "account-b");
    expect(Settings.getCredentialsStored(), isTrue);
    expect(Settings.getSignedOut(), isFalse);
    expect(Auth().getUsername(), "user-account-b");

    // The next start.
    await Auth().resetForTest();
    await _within(Auth().init());

    expect(Auth().loggedIn, isTrue);
    expect((await _within(Auth().getHeaders()))["authorization"],
        "Bearer by-code");
  });

  test("keeps loggingIn false and the lock free while it waits", () async {
    final held = holdPoll();
    final login = codeLogin();
    await _until(() => server.polls.isNotEmpty);
    expect(server.polls, hasLength(1));

    expect(Auth().loggingIn, isFalse);
    await expectLater(
        _within(Auth().getHeaders()), throwsA(isA<AuthException>()));
    expect(await _within(Auth().refreshToken()), isFalse,
        reason: "takes the lock a login holds");

    held.complete(tokens("by-code"));
    expect(await _within(login), isTrue);
    expect(Auth().loggingIn, isFalse);
  });

  test("polls every 5 seconds without an interval, and 5 seconds slower "
      "after slow_down", () async {
    server.onDevice = (_) async => deviceAuthorization(interval: null);
    server.codePolls.addAll([
      () async => pending(),
      () async => oauthError("slow_down"),
      () async => pending(),
    ]);

    expect(await _within(codeLogin()), isTrue);

    final asked = server.arrivals[server.requests.indexOf(server.deviceRequests.single)];
    final at = [asked, for (final p in server.polls) p.$2];
    final gaps = [for (var i = 1; i < at.length; i++) at[i] - at[i - 1]];
    // Timers do not fire early; the slack covers the clock of the fake server.
    const slack = Duration(milliseconds: 2);
    expect(gaps, hasLength(4));
    expect(gaps[0], greaterThanOrEqualTo(_unit * 5 - slack));
    expect(gaps[1], greaterThanOrEqualTo(_unit * 5 - slack));
    expect(gaps[2], greaterThanOrEqualTo(_unit * 10 - slack),
        reason: "slow_down adds 5 seconds");
    expect(gaps[3], greaterThanOrEqualTo(_unit * 10 - slack),
        reason: "and keeps them");
  });

  test("waits a second between polls when the server gives no wait",
      () async {
    Auth.deviceSecond = const Duration(milliseconds: 20);
    server.onDevice = (_) async => deviceAuthorization(interval: 0);
    stillPending(2);

    expect(await _within(codeLogin()), isTrue);

    final at = [for (final p in server.polls) p.$2];
    expect(at, hasLength(3));
    for (var i = 1; i < at.length; i++) {
      expect(at[i] - at[i - 1],
          greaterThanOrEqualTo(const Duration(milliseconds: 18)));
    }
  });

  test("goes on through transport errors, timeouts and 5xx", () async {
    Auth.loginTimeout = const Duration(milliseconds: 50);
    server.codePolls.addAll([
      () async => throw const SocketException("connection reset"),
      () async => throw http.ClientException("connection closed"),
      () async => http.Response("", 503),
      () async => http.Response("<html>", 502,
          headers: {"content-type": "text/html"}),
      () => Completer<http.Response>().future,
      () async => pending(),
    ]);

    expect(await _within(codeLogin()), isTrue);

    expect(server.polls, hasLength(7));
    expect(storedToken(), "by-code");
  });

  final ends = <(String, http.Response, String)>[
    ("access_denied", oauthError("access_denied"), Auth.codeLoginDeclined),
    ("expired_token", oauthError("expired_token"), Auth.codeExpired),
    (
      "unauthorized_client",
      oauthError("unauthorized_client",
          description: "The flow is disabled for the client."),
      Auth.codeLoginDisabled
    ),
    (
      "another OAuth error",
      oauthError("invalid_grant", description: "Invalid device code"),
      "Invalid device code"
    ),
    (
      "an answer that holds no token",
      http.Response("<html>", 200, headers: {"content-type": "text/html"}),
      "Unexpected answer from the auth server"
    ),
    (
      "tokens of another type",
      http.Response('{"access_token": "a", "token_type": "mac"}', 200,
          headers: {"content-type": "application/json"}),
      "Unexpected answer from the auth server"
    ),
  ];
  for (final (answer, response, message) in ends) {
    test("ends at $answer with its message and stores nothing", () async {
      stillPending(1);
      server.codePolls.add(() async => response);

      await expectLater(_within(codeLogin()), _endsWith(message));
      await Future<void>.delayed(_unit * 5);

      expect(server.polls, hasLength(2), reason: "no poll after the end");
      expect(Auth().loggedIn, isFalse);
      expect(storedToken(), isNull);
      expect(Auth().loggingIn, isFalse);
    });
  }

  test("ends once the code expires without an answer", () async {
    server.onDevice = (_) async => deviceAuthorization(expiresIn: 3);
    stillPending(20);

    await expectLater(_within(codeLogin()), _endsWith(Auth.codeExpired));

    expect(server.polls.length, lessThanOrEqualTo(3));
    expect(codes.single.remaining, Duration.zero);
    expect(Auth().loggedIn, isFalse);
  });

  test("caps a lifetime too large for a Duration", () async {
    server.onDevice = (_) async => deviceAuthorization(expiresIn: 1 << 62);

    expect(await _within(codeLogin()), isTrue);

    expect(codes.single.remaining, greaterThan(_unit * 86000));
    expect(codes.single.remaining, lessThanOrEqualTo(_unit * 86400));
  });

  group("at the device authorization", () {
    final refusals = <(String, void Function(FakeAuthServer), String)>[
      (
        "refused for the client",
        (s) => s.onDevice = (_) async => oauthError("unauthorized_client",
            description: "The flow is disabled for the client."),
        Auth.codeLoginDisabled
      ),
      (
        "not offered",
        (s) => s.offersDeviceLogin = false,
        Auth.codeLoginUnavailable
      ),
      (
        "without a discovery",
        (s) => s.discoveryError = const SocketException("no network"),
        "Can't login, are you online?"
      ),
      (
        "unreachable",
        (s) => s.onDevice =
            (_) async => throw const SocketException("no network"),
        "Can't login, are you online?"
      ),
      (
        "answering a 503",
        (s) => s.onDevice = (_) async => http.Response("", 503),
        "Unexpected answer from the auth server"
      ),
      (
        "answering no user code",
        (s) => s.onDevice = (_) async => deviceAuthorization(userCode: " "),
        "Unexpected answer from the auth server"
      ),
      (
        "answering an address that is no web address",
        (s) => s.onDevice = (_) async =>
            deviceAuthorization(verificationUri: "javascript:alert(1)"),
        "Unexpected answer from the auth server"
      ),
      (
        "answering no lifetime",
        (s) => s.onDevice = (_) async => deviceAuthorization(expiresIn: 0),
        "Unexpected answer from the auth server"
      ),
    ];
    for (final (situation, prepare, message) in refusals) {
      test("$situation ends with its message, without a poll", () async {
        prepare(server);

        await expectLater(_within(codeLogin()), _endsWith(message));

        expect(codes, isEmpty);
        expect(server.polls, isEmpty);
        expect(Auth().loggedIn, isFalse);
      });
    }
  });

  group("cancelled", () {
    test("while a poll runs starts no session when it answers late",
        () async {
      final held = holdPoll();
      final login = codeLogin();
      await _until(() => server.polls.isNotEmpty);

      Auth().cancelCodeLogin();
      expect(await _within(login), isFalse);
      held.complete(tokens("by-code"));
      await Future<void>.delayed(_unit * 5);

      expect(server.polls, hasLength(1));
      expect(Auth().loggedIn, isFalse);
      expect(storedToken(), isNull);
    });

    test("while it waits for the next poll sends no further one", () async {
      final login = codeLogin();
      await _until(() => codes.isNotEmpty);

      Auth().cancelCodeLogin();
      expect(await _within(login), isFalse);
      await Future<void>.delayed(_unit * 5);

      expect(server.polls, isEmpty);
      expect(Auth().loggedIn, isFalse);
    });

    test("by a password login keeps that session", () async {
      final held = holdPoll();
      final login = codeLogin();
      await _until(() => server.polls.isNotEmpty);

      await _within(Auth().login("user", "pw"));
      expect(await _within(login), isFalse);
      held.complete(tokens("by-code"));
      await pumpEventQueue();

      expect(Auth().loggedIn, isTrue);
      expect(storedToken(), "signed-in");
    });

    test("by a new code leaves the sign-in to that one", () async {
      final held = holdPoll();
      final first = codeLogin();
      await _until(() => server.polls.isNotEmpty);

      final second = codeLogin();
      expect(await _within(first), isFalse);
      held.complete(tokens("late"));
      expect(await _within(second), isTrue);

      expect(codes, hasLength(2));
      expect(storedToken(), "by-code");
    });
  });

  test("ends at once when a stored session loads meanwhile", () async {
    store.put(credentials("stored"));
    store.readFails = true;
    await _within(Auth().init());
    expect(Auth().loggedIn, isFalse);
    final held = holdPoll();
    final login = codeLogin();
    await _until(() => server.polls.isNotEmpty);

    store.readFails = false;
    expect((await _within(Auth().getHeaders()))["authorization"],
        "Bearer stored");
    expect(await _within(login), isFalse, reason: "before its poll answers");
    held.complete(tokens("by-code"));
    await pumpEventQueue();

    expect(Auth().loggedIn, isTrue);
    expect(storedToken(), "stored");
  });

  test("after a logout signs in and clears the signed-out mark", () async {
    store.put(credentials("valid"));
    await _within(Auth().init());
    await _within(Auth().onLogoutForTest());
    expect(Settings.getSignedOut(), isTrue);

    expect(await _within(codeLogin()), isTrue);

    expect(Auth().loggedIn, isTrue);
    expect(Settings.getSignedOut(), isFalse);
    await Auth().resetForTest();
    await _within(Auth().init());
    expect(Auth().loggedIn, isTrue);
    expect(storedToken(), "by-code");
  });
}
