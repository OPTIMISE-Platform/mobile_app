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
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/exceptions/api_unavailable_exception.dart';
import 'package:mobile_app/exceptions/auth_exception.dart';
import 'package:mobile_app/exceptions/unexpected_status_code_exception.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/services/api_available.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/dio_factory.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/widgets/tabs/nav.dart';
import 'package:openidconnect/openidconnect.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

/// The identity package's own secure storage, as its method channel sees it.
final _identityStorage = <String, String>{};

void _mockIdentityStorage() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('plugins.concerti.io/openidconnect_secure_storage'),
          (call) async {
    final args = (call.arguments as Map?)?.cast<String, Object?>() ?? {};
    final key = args['key'] as String?;
    switch (call.method) {
      case 'write':
        _identityStorage[key!] = args['value'] as String;
        return null;
      case 'read':
        return _identityStorage[key];
      case 'delete':
        _identityStorage.remove(key);
        return null;
      case 'containsKey':
        return _identityStorage.containsKey(key);
    }
    return null;
  });
}

/// An identity of the account the golden environment signs in, or of [sub].
OpenIdIdentity _identity(String accessToken,
    {Duration validFor = const Duration(hours: 1),
    String sub = "test-account"}) {
  String part(Map<String, dynamic> claims) =>
      base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll("=", "");
  return OpenIdIdentity(
    accessToken: accessToken,
    expiresAt: DateTime.now().add(validFor),
    idToken: "${part({"alg": "none"})}.${part({"sub": sub})}.sig",
    tokenType: "bearer",
    refreshToken: "refresh-$accessToken",
  );
}

Future<String?> _storedToken() async =>
    (await OpenIdIdentity.load())?.accessToken;

/// A set-up client whose refresh and logout the test answers.
class _FakeClient extends Fake implements OpenIdConnectClient {
  _FakeClient(this.current, {this.loginIdentity});

  OpenIdIdentity? current;

  /// What a login with credentials signs in.
  final OpenIdIdentity? loginIdentity;
  final events = StreamController<AuthEvent>.broadcast();
  final refreshResult = Completer<bool>();
  final logoutResult = Completer<void>();
  bool disposed = false;

  @override
  Future<OpenIdIdentity> loginWithPassword(
      {required String userName,
      required String password,
      Iterable<String>? prompts,
      Map<String, String>? additionalParameters}) async {
    current = loginIdentity!;
    await current!.save();
    events.add(const AuthEvent(AuthEventTypes.Success));
    return current!;
  }

  /// As the package's: the event, then the revocation, then the clear.
  @override
  Future<void> logout() async {
    events.add(const AuthEvent(AuthEventTypes.LoggingOut));
    await logoutResult.future;
    await clearIdentity();
  }

  @override
  OpenIdIdentity? get identity => current;

  @override
  bool get hasTokenExpired => current!.expiresAt.isBefore(DateTime.now());

  @override
  Stream<AuthEvent> get changes => events.stream;

  @override
  Future<bool> refresh({bool raiseEvents = true}) => refreshResult.future;

  @override
  Future<void> clearIdentity() async {
    if (current == null) return;
    await OpenIdIdentity.clear();
    current = null;
  }

  @override
  void dispose() => disposed = true;
}

/// A client whose password grant answers only once [grant] completes.
class _HangingLoginClient extends _FakeClient {
  _HangingLoginClient(OpenIdIdentity identity)
      : super(null, loginIdentity: identity);

  final grant = Completer<void>();

  @override
  Future<OpenIdIdentity> loginWithPassword(
      {required String userName,
      required String password,
      Iterable<String>? prompts,
      Map<String, String>? additionalParameters}) async {
    await grant.future;
    return super.loginWithPassword(userName: userName, password: password);
  }
}

/// A context whose screen is gone, so the logout does not navigate.
class _Context extends Fake implements BuildContext {
  @override
  bool get mounted => false;
}

const _bound = Duration(milliseconds: 100);

/// Waits for [condition], which storage writes reach only after real I/O.
Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Fails the test instead of letting it hang when [future] does.
Future<T> _within<T>(Future<T> future) =>
    future.timeout(const Duration(seconds: 2));

void main() {
  late List<String> shown;
  final monotonicNow = Auth.monotonicNow;

  setUpAll(() async {
    await setUpGoldenEnvironment();
    _mockIdentityStorage();
  });

  setUp(() {
    shown = [];
    ErrorReporter.resetForTest();
    ErrorReporter.present = shown.add;
    Auth.clientSetupTimeout = _bound;
    Auth.tokenRefreshTimeout = _bound;
  });

  tearDown(() async {
    // Lets a late reconcile of the previous test finish before resetting.
    await pumpEventQueue();
    Auth.createClientOverride = null;
    Auth.serverAvailableOverride = null;
    Auth.monotonicNow = monotonicNow;
    Auth.clientSetupTimeout = const Duration(seconds: 5);
    Auth.tokenRefreshTimeout = const Duration(seconds: 5);
    Auth.loginTimeout = const Duration(seconds: 30);
    Auth.logoutTimeout = const Duration(seconds: 5);
    await Auth().resetForTest();
    resetGoldenBackend();
    resetAppStateForGolden();
    await Settings.setLocalMode(false);
    _identityStorage.clear();
    ErrorReporter.present = (_) {};
  });

  group("getHeaders", () {
    test("a client setup that hangs holds it no longer than its bound",
        () async {
      await _identity("stored").save();
      var setups = 0;
      Auth.createClientOverride = () {
        setups++;
        return Completer<OpenIdConnectClient>().future;
      };
      ApiAvailableService.probeOverride = () async => false;
      Auth().loggedIn = true;

      final headers = await _within(Auth().getHeaders());

      expect(headers["authorization"], "Bearer stored",
          reason: "the stored token stands in for the client");
      await pumpEventQueue();
      expect(ApiAvailableService.isPlatformUnreachable, isTrue,
          reason: "the probe failed as well");
      // The setup mutex is free again, and a setup the user starts waits on
      // the one still running, within its own bound.
      await _within(Auth().init());
      expect(setups, 1);
    });

    test("a setup that never ends is not joined past the login bound",
        () async {
      var now = Duration.zero;
      Auth.monotonicNow = () => now;
      Auth.loginTimeout = const Duration(milliseconds: 200);
      Auth.serverAvailableOverride = () async => true;
      ApiAvailableService.probeOverride = () async => true;
      var setups = 0;
      Auth.createClientOverride = () {
        setups++;
        return setups == 1
            ? Completer<OpenIdConnectClient>().future
            : Future.value(
                _FakeClient(null, loginIdentity: _identity("signed-in")));
      };
      await _within(Auth().init());

      now += const Duration(seconds: 1);
      await _within(Auth().login("user", "pw"));

      expect(setups, 2);
      expect(Auth().loggedIn, isTrue);
    });

    test("a password grant that hangs ends the login within its bound and "
        "keeps no late identity", () async {
      Auth.loginTimeout = const Duration(milliseconds: 200);
      Auth.serverAvailableOverride = () async => true;
      final client = _HangingLoginClient(_identity("late"));
      Auth.createClientOverride = () async => client;

      await expectLater(
          _within(Auth().login("user", "pw")), throwsA(isA<AuthException>()));
      expect(Auth().loggedIn, isFalse);

      client.grant.complete();
      await _until(() => client.disposed);
      await pumpEventQueue();
      expect(await _storedToken(), isNull);
      expect(Auth().loggedIn, isFalse);
    });

    test("a setup that runs into its bound marks nothing while a probe "
        "finds the platform", () async {
      await _identity("stored").save();
      Auth.createClientOverride = () => Completer<OpenIdConnectClient>().future;
      ApiAvailableService.probeOverride = () async => true;
      Auth().loggedIn = true;

      await _within(Auth().getHeaders());
      await pumpEventQueue();

      expect(ApiAvailableService.isPlatformUnreachable, isFalse);
    });

    test("a setup that ends late is taken while no session change came "
        "between", () async {
      await _identity("stored").save();
      final setup = Completer<OpenIdConnectClient>();
      Auth.createClientOverride = () => setup.future;
      ApiAvailableService.probeOverride = () async => true;
      Auth().loggedIn = true;
      await _within(Auth().getHeaders());

      final late = _FakeClient(_identity("fresh"));
      setup.complete(late);
      await _until(() => Auth().clientListenerRegistered);

      expect(late.disposed, isFalse);
      expect(Auth().clientListenerRegistered, isTrue);
      expect(Auth().loggedIn, isTrue);
      expect((await _within(Auth().getHeaders()))["authorization"],
          "Bearer fresh");
    });

    test("a login waits for the setup longer than a background request",
        () async {
      Auth.loginTimeout = const Duration(seconds: 1);
      Auth.serverAvailableOverride = () async => true;
      Auth.createClientOverride = () async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        return _FakeClient(null, loginIdentity: _identity("signed-in"));
      };

      await _within(Auth().login("user", "password"));

      expect(Auth().loggedIn, isTrue);
      expect(await _storedToken(), "signed-in");
    });

    test("a failed setup is tried again after 30 s, not on every request",
        () async {
      await _identity("stored").save();
      var now = Duration.zero;
      Auth.monotonicNow = () => now;
      var setups = 0;
      Auth.createClientOverride = () async {
        setups++;
        throw StateError("invalid discovery document");
      };
      Auth().loggedIn = true;

      await Auth().getHeaders();
      await Auth().getHeaders();
      expect(setups, 1);
      expect(ApiAvailableService.isPlatformUnreachable, isFalse,
          reason: "not a connection failure");

      now += const Duration(seconds: 29);
      await Auth().getHeaders();
      expect(setups, 1);

      now += const Duration(seconds: 2);
      await Auth().getHeaders();
      expect(setups, 2);
    });

    for (final cause in ["the local mode", "an outage"]) {
      test("in $cause sets up nothing and asks no server", () async {
        await _identity("stored").save();
        // Counted, not failed in place: the setup catches what it throws.
        var setups = 0;
        var checks = 0;
        Auth.createClientOverride = () async {
          setups++;
          throw StateError("client setup");
        };
        Auth.serverAvailableOverride = () async {
          checks++;
          return true;
        };
        final backend = FakeBackend();
        serveGoldenBackend(backend);
        Auth.headersOverride = null;
        if (cause == "an outage") {
          ApiAvailableService.setUnreachableForTest(true);
        } else {
          await Settings.setLocalMode(true);
        }
        Auth().loggedIn = true;

        final headers = await _within(Auth().getHeaders());

        expect(headers["authorization"], "Bearer stored");
        expect(setups, 0);
        expect(checks, 0);
        expect(backend.requests, isEmpty);
      });
    }

    test("a setup that succeeds has an outage mark checked again", () async {
      ApiAvailableService.setUnreachableForTest(true);
      ApiAvailableService.probeOverride = () async => true;
      Auth.createClientOverride = () async => _FakeClient(_identity("fresh"));

      await _within(Auth().init());

      expect(ApiAvailableService.isPlatformUnreachable, isFalse);
      expect(Auth().loggedIn, isTrue);
    });

    test("a refresh that hangs is abandoned with its client", () async {
      final client = _FakeClient(
          _identity("expired", validFor: const Duration(minutes: -1)));
      await client.current!.save();
      Auth.createClientOverride = () async => client;
      Auth.serverAvailableOverride = () async => true;
      ApiAvailableService.probeOverride = () async => false;
      Auth().loggedIn = true;

      expect(await _within(Auth().getHeaders()), isEmpty,
          reason: "a refresh that did not finish yields no token, as before");
      await pumpEventQueue();
      expect(ApiAvailableService.isPlatformUnreachable, isTrue);
      expect(Auth().clientListenerRegistered, isFalse,
          reason: "the client's late events must not reach the session");
      expect((await _within(Auth().getHeaders()))["authorization"],
          "Bearer expired");
    });

    test("a refresh that runs into its bound marks nothing while a probe "
        "finds the platform", () async {
      final client = _FakeClient(
          _identity("expired", validFor: const Duration(minutes: -1)));
      await client.current!.save();
      Auth.createClientOverride = () async => client;
      Auth.serverAvailableOverride = () async => true;
      ApiAvailableService.probeOverride = () async => true;
      Auth().loggedIn = true;

      await _within(Auth().getHeaders());
      await pumpEventQueue();

      expect(ApiAvailableService.isPlatformUnreachable, isFalse);
    });
  });

  test("the discovery URL follows the settings", () async {
    addTearDown(() => Settings.setKeycloakUrl(null));
    await Settings.setKeycloakUrl("https://auth-one.test");
    expect(Auth().discoveryUrl, startsWith("https://auth-one.test/"));

    await Settings.setKeycloakUrl("https://auth-two.test");
    expect(Auth().discoveryUrl, startsWith("https://auth-two.test/"));
  });

  test("a logout without a client still logs out", () async {
    await _identity("stored").save();
    Auth.createClientOverride = () async => throw StateError("no client");
    Auth.serverAvailableOverride = () async => false;
    Auth().loggedIn = true;

    await _within(Auth().logout(_Context()) as Future);

    expect(Auth().loggedIn, isFalse);
    expect(await _storedToken(), isNull);
  });

  test("a logout in an outage sets up no client", () async {
    await _identity("stored").save();
    var setups = 0;
    Auth.createClientOverride = () {
      setups++;
      return Completer<OpenIdConnectClient>().future;
    };
    Auth.serverAvailableOverride = () async => false;
    ApiAvailableService.setUnreachableForTest(true);
    Auth().loggedIn = true;

    await _within(Auth().logout(_Context()) as Future);

    expect(setups, 0);
    expect(Auth().loggedIn, isFalse);
    expect(await _storedToken(), isNull);
  });

  test("a logout in an outage does not wait for the revocation", () async {
    final client = _FakeClient(_identity("valid"));
    await client.current!.save();
    Auth.createClientOverride = () async => client;
    Auth.serverAvailableOverride = () async => false;
    Auth.logoutTimeout = const Duration(seconds: 10);
    await _within(Auth().init());
    ApiAvailableService.setUnreachableForTest(true);

    await _within(Auth().logout(_Context()) as Future);

    expect(Auth().loggedIn, isFalse);
    expect(await _storedToken(), isNull);
  });

  test("a logout whose revocation hangs logs out locally", () async {
    final client = _FakeClient(_identity("valid"));
    await client.current!.save();
    Auth.createClientOverride = () async => client;
    Auth.serverAvailableOverride = () async => true;
    Auth.logoutTimeout = _bound;
    await _within(Auth().init());
    expect(Auth().loggedIn, isTrue);

    await _within(Auth().logout(_Context()) as Future);

    expect(Auth().loggedIn, isFalse);
    expect(await _storedToken(), isNull);
    expect(Auth().clientListenerRegistered, isFalse,
        reason: "the client is dropped, as by an offline logout");
    expect(client.current, isNull,
        reason: "its own late clear finds no identity left");

    client.logoutResult.complete();
    await pumpEventQueue();
    expect(client.disposed, isTrue);
  });

  test("a refresh that ends after an offline logout does not sign the next "
      "login in as that account", () async {
    // Signed in as A; the refresh runs into its bound and its client is
    // abandoned, the refresh still running.
    final a = _FakeClient(_identity("a-expired",
        validFor: const Duration(minutes: -1), sub: "account-a"));
    await a.current!.save();
    Auth.createClientOverride = () async => a;
    Auth.serverAvailableOverride = () async => true;
    ApiAvailableService.probeOverride = () async => false;
    Auth().loggedIn = true;
    await _within(Auth().getHeaders());
    await pumpEventQueue();
    expect(ApiAvailableService.isPlatformUnreachable, isTrue);

    // A logs out while the platform is down.
    Auth.serverAvailableOverride = () async => false;
    await _within(Auth().logout(_Context()) as Future);
    expect(await _storedToken(), isNull);

    // The platform is back, and B logs in. The setup loads the stored
    // identity once it has the discovery document, as the package's does.
    ApiAvailableService.probeOverride = () async => true;
    await ApiAvailableService().recheckPlatform();
    Auth.serverAvailableOverride = () async => true;
    final discovery = Completer<void>();
    Auth.createClientOverride = () async {
      await discovery.future;
      return _FakeClient(await OpenIdIdentity.load(),
          loginIdentity: _identity("b", sub: "account-b"));
    };
    final login = Auth().login("b", "password");
    await pumpEventQueue();

    // Meanwhile A's abandoned refresh ends and stores A's identity.
    a.current = _identity("a-refreshed", sub: "account-a");
    await a.current!.save();
    a.refreshResult.complete(true);
    await pumpEventQueue();
    discovery.complete();
    await _within(login);
    await pumpEventQueue();

    expect(Auth().getUsername(), "account-b");
    expect(Settings.getAccount(), "account-b");
    expect(await _storedToken(), "b");
  });

  test("a login whose setup fails after a logout does not trust an identity "
      "stored meanwhile", () async {
    Auth.serverAvailableOverride = () async => false;
    Auth().loggedIn = true;
    await Auth().onLogoutForTest();
    // As a refresh abandoned before the logout stores when it ends.
    await _identity("late", sub: "account-a").save();
    Auth.createClientOverride = () async => throw StateError("no client");

    await expectLater(Auth().login("b", "password"), throwsA(anything));

    expect(Auth().loggedIn, isFalse);
  });

  group("an abandoned call that ends late", () {
    test("does not sign a logged-out session back in", () async {
      await _identity("stored").save();
      final setup = Completer<OpenIdConnectClient>();
      Auth.createClientOverride = () => setup.future;
      Auth().loggedIn = true;
      await _within(Auth().getHeaders());

      Auth.serverAvailableOverride = () async => false;
      await Auth().onLogoutForTest();
      expect(await _storedToken(), isNull);

      // The setup refreshed on its way, which stores the identity it got.
      final late = _FakeClient(_identity("late"));
      await late.current!.save();
      setup.complete(late);
      await pumpEventQueue();

      expect(late.disposed, isTrue);
      expect(await _storedToken(), isNull);
      expect(Auth().loggedIn, isFalse);
      expect(Auth().clientListenerRegistered, isFalse);
    });

    test("puts back the stored identity it cleared on a failure", () async {
      final client = _FakeClient(
          _identity("expired", validFor: const Duration(minutes: -1)));
      await client.current!.save();
      Auth.createClientOverride = () async => client;
      Auth.serverAvailableOverride = () async => true;
      Auth().loggedIn = true;
      await _within(Auth().getHeaders());

      // The refresh failed on an expired identity, which clears it.
      await client.clearIdentity();
      client.refreshResult.complete(false);
      await pumpEventQueue();

      expect(await _storedToken(), "expired");
      expect(Auth().loggedIn, isTrue);
    });

    test("a late refresh after a logout leaves the identity cleared",
        () async {
      final client = _FakeClient(
          _identity("expired", validFor: const Duration(minutes: -1)));
      await client.current!.save();
      Auth.createClientOverride = () async => client;
      Auth.serverAvailableOverride = () async => true;
      Auth().loggedIn = true;
      await _within(Auth().getHeaders());

      Auth.serverAvailableOverride = () async => false;
      await Auth().onLogoutForTest();
      client.current = _identity("refreshed");
      await client.current!.save();
      client.events.add(const AuthEvent(AuthEventTypes.Refresh));
      client.refreshResult.complete(true);
      await pumpEventQueue();

      expect(client.disposed, isTrue);
      expect(await _storedToken(), isNull);
      expect(Auth().loggedIn, isFalse);
    });

    test("a late refresh in the same session keeps what it stored", () async {
      final client = _FakeClient(
          _identity("expired", validFor: const Duration(minutes: -1)));
      await client.current!.save();
      Auth.createClientOverride = () async => client;
      Auth.serverAvailableOverride = () async => true;
      Auth().loggedIn = true;
      await _within(Auth().getHeaders());

      client.current = _identity("refreshed");
      await client.current!.save();
      client.refreshResult.complete(true);
      await pumpEventQueue();

      expect(await _storedToken(), "refreshed");
      expect(Auth().loggedIn, isTrue);
    });
  });

  group("the outage state", () {
    late FakeBackend backend;

    setUp(() {
      backend = FakeBackend();
      serveGoldenBackend(backend);
    });

    Future<Object?> get(String url) async {
      final dio = await DioFactory.create(DioConfig.standard);
      try {
        await dio.get(url);
        return null;
      } catch (e) {
        return e;
      }
    }

    test("is set by a platform request that got no answer or a gateway error",
        () async {
      backend.serveJson("GET", "/refused", 403, null);
      await get("https://localhost/refused");
      expect(ApiAvailableService.isPlatformUnreachable, isFalse,
          reason: "a refusal is an answer");

      for (final status in [502, 503, 504]) {
        ApiAvailableService.resetForTest();
        ApiAvailableService.probeOverride = () async => false;
        backend.serveJson("GET", "/ingress", status, null);
        await get("https://localhost/ingress");
        await pumpEventQueue();
        expect(ApiAvailableService.isPlatformUnreachable, isTrue,
            reason: "$status and a failed probe");
      }

      for (final type in [
        DioExceptionType.connectionError,
        DioExceptionType.connectionTimeout
      ]) {
        ApiAvailableService.resetForTest();
        backend.failures["GET /down"] = type;
        await get("https://localhost/down");
        expect(ApiAvailableService.isPlatformUnreachable, isTrue,
            reason: type.name);
      }
    });

    test("is not set by a gateway error of one service while a probe finds "
        "the platform", () async {
      ApiAvailableService.probeOverride = () async => true;
      for (final status in [502, 503, 504]) {
        backend.serveJson("GET", "/one-service", status, null);
        await get("https://localhost/one-service");
        await pumpEventQueue();
        expect(ApiAvailableService.isPlatformUnreachable, isFalse,
            reason: "$status");
      }
    });

    test("is not set by a gateway that does not answer", () async {
      backend.failures["GET /core"] = DioExceptionType.connectionError;
      await get("http://gw.test/core");
      expect(ApiAvailableService.isPlatformUnreachable, isFalse);
    });

    test("is not set by a request the local mode refused", () async {
      await Settings.setLocalMode(true);
      final error = await get("https://localhost/x");
      expect((error as DioException).error, isA<ApiUnavailableException>());
      expect(ApiAvailableService.isPlatformUnreachable, isFalse);
    });

    test("a slow answer counts only when a probe fails as well", () async {
      backend.failures["GET /slow"] = DioExceptionType.receiveTimeout;
      ApiAvailableService.probeOverride = () async => true;
      await get("https://localhost/slow");
      await pumpEventQueue();
      expect(ApiAvailableService.isPlatformUnreachable, isFalse);

      ApiAvailableService.probeOverride = () async => false;
      await get("https://localhost/slow");
      await pumpEventQueue();
      expect(ApiAvailableService.isPlatformUnreachable, isTrue);
    });

    test("refuses platform requests at once and lets gateway requests pass",
        () async {
      AppState().networks.add(Network("n1", "Home", false, const [],
          const [], DeviceConnectionStatus.online, "", "owner-1")
        ..localGateways = [MGW("gw.test", "gw.test", "", "gw.test")]);
      backend.serveJson("GET", "/core", 200, {});
      ApiAvailableService.setUnreachableForTest(true);

      final error = await get("https://localhost/x");
      expect((error as DioException).error, isA<ApiUnavailableException>());
      expect(await get("http://gw.test/core"), isNull);
      expect(backend.requests.map((r) => r.uri.host), ["gw.test"]);
    });

    test("is cleared by a probe that succeeds, which stops the rechecks",
        () async {
      ApiAvailableService.recheckInterval = const Duration(milliseconds: 20);
      var probes = 0;
      var reachable = false;
      ApiAvailableService.probeOverride = () async {
        probes++;
        return reachable;
      };
      ApiAvailableService().markPlatformUnreachable();

      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(probes, greaterThan(1), reason: "rechecked while unreachable");
      expect(ApiAvailableService.isPlatformUnreachable, isTrue);

      reachable = true;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(ApiAvailableService.isPlatformUnreachable, isFalse);
      expect(ApiAvailableService.rechecking, isFalse,
          reason: "no timer while reachable");
    });

    test("a failure from before the platform was found again is dropped",
        () async {
      // Leaves while the platform counts as reachable, and fails only after
      // an outage was recorded and a probe found the platform again.
      final hold = Completer<void>();
      backend.holds["GET /late"] = hold;
      backend.failures["GET /late"] = DioExceptionType.connectionError;
      final running = get("https://localhost/late");
      await pumpEventQueue();

      ApiAvailableService().markPlatformUnreachable();
      ApiAvailableService.probeOverride = () async => true;
      await ApiAvailableService().recheckPlatform();
      hold.complete();
      await running;

      expect(ApiAvailableService.isPlatformUnreachable, isFalse);
    });

    test("runs no recheck timer in the local mode", () async {
      ApiAvailableService.probeOverride = () async => false;
      await Settings.setLocalMode(true);
      ApiAvailableService().markPlatformUnreachable();
      expect(ApiAvailableService.rechecking, isFalse);

      // As the settings switch does.
      await Settings.setLocalMode(false);
      await ApiAvailableService().recheckPlatform();
      expect(ApiAvailableService.rechecking, isTrue,
          reason: "the probe failed, so the rechecks start");

      await Settings.setLocalMode(true);
      await ApiAvailableService().recheckPlatform();
      expect(ApiAvailableService.rechecking, isFalse);
    });

    test("is not probed in the local mode", () async {
      var probes = 0;
      ApiAvailableService.probeOverride = () async {
        probes++;
        return true;
      };
      ApiAvailableService.setUnreachableForTest(true);
      await Settings.setLocalMode(true);

      await ApiAvailableService().recheckPlatform();

      expect(probes, 0);
      expect(ApiAvailableService.isPlatformUnreachable, isTrue);
    });

    test("locks the platform tabs and tells AppState's listeners", () async {
      var notified = 0;
      void count() => notified++;
      AppState().addListener(count);
      addTearDown(() => AppState().removeListener(count));

      expect(AppState().setAndGetDisabledTabs()[tabSmartServices], isFalse);
      ApiAvailableService.setUnreachableForTest(true);

      expect(notified, 1);
      expect(AppState().setAndGetDisabledTabs()[tabSmartServices], isTrue);
    });
  });

  group("error reporting", () {
    DioException connectionFailure() => DioException(
        requestOptions: RequestOptions(path: "/x"),
        type: DioExceptionType.connectionError);

    test("an outage is logged but not toasted", () {
      ApiAvailableService.setUnreachableForTest(true);

      ErrorReporter.report("Could not get devices", connectionFailure());
      ErrorReporter.reportOffline();
      ErrorReporter.report("Could not get devices", ApiUnavailableException());
      expect(shown, isEmpty);

      ErrorReporter.report(
          "Could not load devices", UnexpectedStatusCodeException(500, "x"));
      expect(shown, ["Could not load devices"],
          reason: "an answer from the platform is still shown");
    });

    test("the local mode does not toast what it refused", () async {
      await Settings.setLocalMode(true);

      ErrorReporter.report("Could not get devices", ApiUnavailableException());

      expect(shown, isEmpty);
    });
  });
}
