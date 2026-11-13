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

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
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

import 'fake_auth_server.dart';
import 'fake_backend.dart';
import 'golden_helper.dart';

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
  late FakeAuthServer server;
  late SecureStore store;
  final monotonicNow = Auth.monotonicNow;

  String? storedToken() => store.stored?.accessToken;

  /// Signs in on [stored], as the app start does.
  Future<void> start(String stored,
      {Duration validFor = const Duration(hours: 1),
      String sub = "test-account",
      bool discovered = true}) async {
    store.put(credentials(stored,
        validFor: validFor, sub: sub, discovered: discovered));
    await _within(Auth().init());
  }

  const expired = Duration(minutes: -1);

  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  setUp(() {
    shown = [];
    ErrorReporter.resetForTest();
    ErrorReporter.present = shown.add;
    Auth.clientSetupTimeout = _bound;
    Auth.tokenRefreshTimeout = _bound;
    server = FakeAuthServer()..install();
    store = SecureStore()..install();
    LegacyIdentityStore().install();
  });

  tearDown(() async {
    // Lets a late settle of the previous test finish before resetting.
    await pumpEventQueue();
    FakeAuthServer.uninstall();
    LegacyIdentityStore.uninstall();
    Auth.serverAvailableOverride = null;
    Auth.monotonicNow = monotonicNow;
    Auth.clientSetupTimeout = const Duration(seconds: 5);
    Auth.tokenRefreshTimeout = const Duration(seconds: 5);
    Auth.loginTimeout = const Duration(seconds: 30);
    Auth.logoutTimeout = const Duration(seconds: 5);
    await Auth().resetForTest();
    // Survives resetForTest, as across a start; set by the logouts here.
    await Settings.setSignedOut(false);
    resetGoldenBackend();
    resetAppStateForGolden();
    await Settings.setLocalMode(false);
    ErrorReporter.present = (_) {};
  });

  group("getHeaders", () {
    test("a discovery that hangs holds it no longer than its bound, and a "
        "login waits on the one still running", () async {
      // Moved from the previous package, so without the token endpoint.
      await start("stored", validFor: expired, discovered: false);
      server.holdDiscovery = Completer<void>();
      Auth.serverAvailableOverride = () async => true;
      ApiAvailableService.probeOverride = () async => false;

      final headers = await _within(Auth().getHeaders());

      expect(headers, isEmpty,
          reason: "a refresh that did not happen yields no token, as before");
      await pumpEventQueue();
      expect(ApiAvailableService.isPlatformUnreachable, isTrue,
          reason: "the probe failed as well");
      expect(Auth().loggedIn, isTrue);
      expect(storedToken(), "stored");
      // The login waits on the discovery still running, within its own
      // bound.
      Auth.loginTimeout = const Duration(milliseconds: 300);
      await expectLater(_within(Auth().login("user", "pw")),
          throwsA(isA<AuthException>()));
      expect(server.discoveries, 1);
      expect(Auth().loggedIn, isTrue, reason: "a failed login keeps the session");
    });

    test("a discovery that never ends is not joined past the login bound",
        () async {
      var now = Duration.zero;
      Auth.monotonicNow = () => now;
      Auth.loginTimeout = const Duration(milliseconds: 200);
      Auth.serverAvailableOverride = () async => true;
      ApiAvailableService.probeOverride = () async => true;
      server.holdDiscovery = Completer<void>();
      await expectLater(_within(Auth().login("user", "pw")),
          throwsA(isA<AuthException>()));

      now += const Duration(seconds: 1);
      server.holdDiscovery = null;
      await _within(Auth().login("user", "pw"));

      expect(server.discoveries, 2);
      expect(Auth().loggedIn, isTrue);
    });

    test("a password grant that hangs ends the login within its bound and "
        "keeps no late identity", () async {
      Auth.loginTimeout = const Duration(milliseconds: 200);
      Auth.serverAvailableOverride = () async => true;
      server.holdToken = Completer<void>();

      await expectLater(
          _within(Auth().login("user", "pw")), throwsA(isA<AuthException>()));
      expect(Auth().loggedIn, isFalse);

      server.holdToken!.complete();
      await _until(() => server.tokenRequests.isNotEmpty);
      await pumpEventQueue();
      expect(storedToken(), isNull);
      expect(Auth().loggedIn, isFalse);
    });

    test("a discovery that runs into its bound marks nothing while a probe "
        "finds the platform", () async {
      await start("stored", validFor: expired, discovered: false);
      server.holdDiscovery = Completer<void>();
      Auth.serverAvailableOverride = () async => true;
      ApiAvailableService.probeOverride = () async => true;

      await _within(Auth().getHeaders());
      await pumpEventQueue();

      expect(ApiAvailableService.isPlatformUnreachable, isFalse);
    });

    test("a discovery that ends late is taken while no session change came "
        "between", () async {
      await start("stored", validFor: expired, discovered: false);
      server.holdDiscovery = Completer<void>();
      Auth.serverAvailableOverride = () async => true;
      ApiAvailableService.probeOverride = () async => true;
      await _within(Auth().getHeaders());

      server.holdDiscovery!.complete();
      await pumpEventQueue();

      expect(Auth().loggedIn, isTrue);
      expect((await _within(Auth().getHeaders()))["authorization"],
          "Bearer refreshed");
      expect(server.discoveries, 1, reason: "the late answer was kept");
      expect(storedToken(), "refreshed");
      expect(store.stored!.tokenEndpoint, tokenEndpoint,
          reason: "the refreshed credentials carry the endpoint");
    });

    test("a login waits for the discovery longer than a background request",
        () async {
      Auth.loginTimeout = const Duration(seconds: 1);
      Auth.serverAvailableOverride = () async => true;
      server.holdDiscovery = Completer<void>();
      unawaited(Future<void>.delayed(const Duration(milliseconds: 300))
          .then((_) => server.holdDiscovery!.complete()));

      await _within(Auth().login("user", "password"));

      expect(Auth().loggedIn, isTrue);
      expect(storedToken(), "signed-in");
    });

    test("a failed discovery is tried again after 30 s, not on every request",
        () async {
      await start("stored", validFor: expired, discovered: false);
      var now = Duration.zero;
      Auth.monotonicNow = () => now;
      Auth.serverAvailableOverride = () async => true;
      server.discoveryStatus = 500;

      await Auth().getHeaders();
      await Auth().getHeaders();
      expect(server.discoveries, 1);
      expect(ApiAvailableService.isPlatformUnreachable, isFalse,
          reason: "not a connection failure");

      now += const Duration(seconds: 29);
      await Auth().getHeaders();
      expect(server.discoveries, 1);

      now += const Duration(seconds: 2);
      await Auth().getHeaders();
      expect(server.discoveries, 2);
      expect(Auth().loggedIn, isTrue);
    });

    for (final cause in ["the local mode", "an outage"]) {
      test("in $cause asks no server", () async {
        await start("stored", validFor: expired);
        var checks = 0;
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

        final headers = await _within(Auth().getHeaders());

        expect(headers["authorization"], "Bearer stored");
        expect(server.requests, isEmpty);
        expect(checks, 0);
        expect(backend.requests, isEmpty);
      });
    }

    test("a login that reaches the auth server has an outage mark checked "
        "again", () async {
      ApiAvailableService.setUnreachableForTest(true);
      ApiAvailableService.probeOverride = () async => true;
      Auth.serverAvailableOverride = () async => true;

      await _within(Auth().login("user", "pw"));

      expect(ApiAvailableService.isPlatformUnreachable, isFalse);
      expect(Auth().loggedIn, isTrue);
    });

    test("a refresh that hangs is bounded, and the next one waits on it "
        "instead of sending the refresh token again", () async {
      await start("expired", validFor: expired);
      server.holdToken = Completer<void>();
      Auth.serverAvailableOverride = () async => true;
      ApiAvailableService.probeOverride = () async => false;

      expect(await _within(Auth().getHeaders()), isEmpty,
          reason: "a refresh that did not finish yields no token, as before");
      await pumpEventQueue();
      expect(ApiAvailableService.isPlatformUnreachable, isTrue);
      expect((await _within(Auth().getHeaders()))["authorization"],
          "Bearer expired");

      expect(await _within(Auth().refreshToken()), isFalse);
      expect(server.tokenRequests, hasLength(1));
      expect(Auth().loggedIn, isTrue);
    });

    test("a refresh that runs into its bound marks nothing while a probe "
        "finds the platform", () async {
      await start("expired", validFor: expired);
      server.holdToken = Completer<void>();
      Auth.serverAvailableOverride = () async => true;
      ApiAvailableService.probeOverride = () async => true;

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

  test("a logout whose auth server does not answer still logs out", () async {
    await start("stored");
    server.discoveryError = const SocketException("connection refused");
    Auth.serverAvailableOverride = () async => false;

    await _within(Auth().logout(_Context()));

    expect(Auth().loggedIn, isFalse);
    expect(storedToken(), isNull);
    expect(server.revocations, isEmpty);
  });

  test("a logout revokes the refresh token as a public client", () async {
    await start("valid");
    Auth.serverAvailableOverride = () async => true;

    await _within(Auth().logout(_Context()));

    expect(server.revocations, [
      {
        "token": "refresh-valid",
        "token_type_hint": "refresh_token",
        "client_id": dotenv.env["KEYCLOAK_CLIENTID"],
      }
    ]);
    expect(Auth().loggedIn, isFalse);
    expect(storedToken(), isNull);
  });

  test("a logout in an outage asks no server", () async {
    await start("stored");
    Auth.serverAvailableOverride = () async => false;
    ApiAvailableService.setUnreachableForTest(true);

    await _within(Auth().logout(_Context()));

    expect(server.requests, isEmpty);
    expect(Auth().loggedIn, isFalse);
    expect(storedToken(), isNull);
  });

  test("a logout in an outage does not wait for the revocation", () async {
    await start("valid");
    server.holdRevocation = Completer<void>();
    Auth.serverAvailableOverride = () async => false;
    Auth.logoutTimeout = const Duration(seconds: 10);
    ApiAvailableService.setUnreachableForTest(true);

    await _within(Auth().logout(_Context()));

    expect(Auth().loggedIn, isFalse);
    expect(storedToken(), isNull);
  });

  test("a logout whose revocation hangs logs out locally", () async {
    await start("valid");
    server.holdRevocation = Completer<void>();
    Auth.serverAvailableOverride = () async => true;
    Auth.logoutTimeout = _bound;
    expect(Auth().loggedIn, isTrue);

    await _within(Auth().logout(_Context()));

    expect(Auth().loggedIn, isFalse);
    expect(storedToken(), isNull);

    // A login meanwhile keeps its session when the revocation ends.
    await _within(Auth().login("user", "pw"));
    server.holdRevocation!.complete();
    await pumpEventQueue();
    expect(server.revocations, hasLength(1));
    expect(Auth().loggedIn, isTrue);
    expect(storedToken(), "signed-in");
  });

  test("a refresh that ends after an offline logout does not sign the next "
      "login in as that account", () async {
    // Signed in as A; the refresh runs into its bound, the refresh still
    // running.
    await start("a-expired", validFor: expired, sub: "account-a");
    final refreshOfA = Completer<void>();
    server.onToken = (form) async {
      if (form["grant_type"] == "refresh_token") {
        await refreshOfA.future;
        return tokens("a-refreshed", sub: "account-a");
      }
      return tokens("b", sub: "account-b");
    };
    Auth.serverAvailableOverride = () async => true;
    ApiAvailableService.probeOverride = () async => false;
    await _within(Auth().getHeaders());
    await pumpEventQueue();
    expect(ApiAvailableService.isPlatformUnreachable, isTrue);

    // A logs out while the platform is down.
    Auth.serverAvailableOverride = () async => false;
    await _within(Auth().logout(_Context()));
    expect(storedToken(), isNull);

    // The platform is back, and B logs in; the discovery holds the login
    // until A's refresh has ended.
    ApiAvailableService.probeOverride = () async => true;
    await ApiAvailableService().recheckPlatform();
    Auth.serverAvailableOverride = () async => true;
    server.holdDiscovery = Completer<void>();
    final login = Auth().login("b", "password");
    await pumpEventQueue();

    refreshOfA.complete();
    await pumpEventQueue();
    server.holdDiscovery!.complete();
    await _within(login);
    await pumpEventQueue();

    expect(Auth().getUsername(), "user-account-b");
    expect(Settings.getAccount(), "account-b");
    expect(storedToken(), "b");
  });

  test("a login after a logout does not trust credentials stored meanwhile",
      () async {
    Auth.serverAvailableOverride = () async => false;
    await start("a", sub: "account-a");
    await Auth().onLogoutForTest();
    // As a deletion that did not take leaves them.
    store.put(credentials("late", sub: "account-a"));
    server.discoveryError = StateError("no discovery");

    await expectLater(Auth().login("b", "password"), throwsA(anything));

    expect(Auth().loggedIn, isFalse);
  });

  group("a refresh that ends late", () {
    test("does not sign a logged-out session back in", () async {
      await start("expired", validFor: expired);
      server.holdToken = Completer<void>();
      Auth.serverAvailableOverride = () async => true;
      ApiAvailableService.probeOverride = () async => true;
      await _within(Auth().getHeaders());

      Auth.serverAvailableOverride = () async => false;
      await Auth().onLogoutForTest();
      expect(storedToken(), isNull);

      server.holdToken!.complete();
      await _until(() => server.tokenRequests.isNotEmpty);
      await pumpEventQueue();

      expect(storedToken(), isNull);
      expect(Auth().loggedIn, isFalse);
      expect(Settings.getAccount(), "test-account");
    });

    test("keeps the stored credentials when it failed", () async {
      await start("expired", validFor: expired);
      server.holdToken = Completer<void>();
      server.tokenError = const SocketException("connection reset");
      Auth.serverAvailableOverride = () async => true;
      ApiAvailableService.probeOverride = () async => true;
      await _within(Auth().getHeaders());

      server.holdToken!.complete();
      await pumpEventQueue();

      expect(storedToken(), "expired");
      expect(Auth().loggedIn, isTrue);
    });

    test("with invalid_grant after the next login leaves that session alone",
        () async {
      await start("expired", validFor: expired);
      final refresh = Completer<void>();
      server.onToken = (form) async {
        if (form["grant_type"] == "refresh_token") {
          await refresh.future;
          return oauthError("invalid_grant", description: "Token is not active");
        }
        return tokens("next");
      };
      Auth.serverAvailableOverride = () async => true;
      ApiAvailableService.probeOverride = () async => true;
      await _within(Auth().getHeaders());

      Auth.serverAvailableOverride = () async => false;
      await Auth().onLogoutForTest();
      Auth.serverAvailableOverride = () async => true;
      await _within(Auth().login("user", "pw"));
      refresh.complete();
      await pumpEventQueue();

      expect(Auth().loggedIn, isTrue);
      expect(storedToken(), "next");
    });

    test("in the same session keeps what it got", () async {
      await start("expired", validFor: expired);
      server.holdToken = Completer<void>();
      Auth.serverAvailableOverride = () async => true;
      ApiAvailableService.probeOverride = () async => true;
      await _within(Auth().getHeaders());

      server.holdToken!.complete();
      await pumpEventQueue();

      expect(storedToken(), "refreshed",
          reason: "a rotated refresh token leaves the previous one invalid");
      expect(Auth().loggedIn, isTrue);
      expect((await _within(Auth().getHeaders()))["authorization"],
          "Bearer refreshed");
      expect(server.tokenRequests, hasLength(1));
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
