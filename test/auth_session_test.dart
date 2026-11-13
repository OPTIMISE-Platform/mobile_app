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
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http_cache_hive_store/http_cache_hive_store.dart';
import 'package:mobile_app/exceptions/auth_exception.dart';
import 'package:mobile_app/live/client_certificate.dart';
import 'package:mobile_app/services/api_available.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/account_epoch.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'fake_auth_server.dart';
import 'fake_backend.dart';
import 'golden_helper.dart';

const _bound = Duration(milliseconds: 100);

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

Future<T> _within<T>(Future<T> future) =>
    future.timeout(const Duration(seconds: 2));

/// A response as the HTTP cache keeps it.
CacheResponse _cached(String key) => CacheResponse(
      cacheControl: CacheControl(),
      content: [1],
      date: null,
      eTag: null,
      expires: null,
      headers: null,
      key: key,
      lastModified: null,
      maxStale: null,
      priority: CachePriority.normal,
      requestDate: DateTime.now(),
      responseDate: DateTime.now(),
      url: "https://localhost/$key",
      statusCode: 200,
    );

/// path_provider never answering, so the cache clear of a logout hangs.
class _HangingPathProvider extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() => Completer<String?>().future;

  @override
  Future<List<String>?> getExternalCachePaths() =>
      Completer<List<String>?>().future;
}

/// Secure storage whose deletion of the credentials throws, or with
/// [deletesNothing] reports success without deleting, as Android's can.
class _UndeletableStore extends SecureStore {
  _UndeletableStore(super.log);

  bool deleteFails = false;
  bool deletesNothing = false;
  int deletions = 0;

  @override
  String? remove(Object? key) {
    if (key == Auth.storageKeys.credentials) {
      deletions++;
      if (deleteFails) throw PlatformException(code: "keystore");
      if (deletesNothing) return data[key];
    }
    return super.remove(key);
  }
}

/// A logout from a screen that is gone by the time it ends.
class _GoneContext extends Fake implements BuildContext {
  @override
  bool get mounted => false;
}

/// path_provider failing, so the cache clear of a logout throws.
class _FailingPathProvider extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() =>
      Future.error(const FileSystemException("no documents directory"));

  @override
  Future<List<String>?> getExternalCachePaths() =>
      Future.error(const FileSystemException("no cache directory"));
}

void main() {
  late FakeAuthServer server;
  late SecureStore store;
  late LegacyIdentityStore legacy;
  // Writes and deletes of both stores, in order.
  late List<String> log;
  const expired = Duration(minutes: -1);
  final monotonicNow = Auth.monotonicNow;
  final credentialsKey = Auth.storageKeys.credentials;
  final migratedKey = Auth.storageKeys.legacyMigrated;

  String? storedToken() => store.stored?.accessToken;

  Future<void> start(String stored,
      {Duration validFor = const Duration(hours: 1)}) async {
    store.put(credentials(stored, validFor: validFor));
    await _within(Auth().init());
  }

  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  setUp(() async {
    log = [];
    server = FakeAuthServer()..install();
    store = SecureStore(log)..install();
    legacy = LegacyIdentityStore(log)..install();
    Auth.serverAvailableOverride = () async => true;
    Auth.clientSetupTimeout = _bound;
    Auth.tokenRefreshTimeout = _bound;
    ApiAvailableService.probeOverride = () async => true;
    await Settings.setAccount("test-account");
    // Set by the sessions and logouts of earlier tests.
    await Settings.setCredentialsStored(false);
    await Settings.setSignedOut(false);
  });

  tearDown(() async {
    await pumpEventQueue();
    FakeAuthServer.uninstall();
    LegacyIdentityStore.uninstall();
    Auth.serverAvailableOverride = null;
    Auth.clientSetupTimeout = const Duration(seconds: 5);
    Auth.tokenRefreshTimeout = const Duration(seconds: 5);
    Auth.loginTimeout = const Duration(seconds: 30);
    Auth.monotonicNow = monotonicNow;
    await Auth().resetForTest();
    ApiAvailableService.resetForTest();
  });

  group("a login", () {
    test("sends the password grant as a public client and stores the session",
        () async {
      await _within(Auth().login("user", "pw"));

      final request = server.tokenHttpRequests.single;
      expect(request.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains("authorization")),
          reason: "no client secret, so no basic auth");
      expect(request.bodyFields, {
        "grant_type": "password",
        "username": "user",
        "password": "pw",
        "client_id": dotenv.env["KEYCLOAK_CLIENTID"],
        "scope": "offline_access openid profile email",
      });
      expect(Auth().loggedIn, isTrue);
      expect(storedToken(), "signed-in");
      expect(store.stored!.tokenEndpoint, tokenEndpoint);
      expect(Settings.getAccount(), "test-account");
      expect(Auth().getUsername(), "user-test-account");
    });

    test("refused for its credentials says so and stores nothing", () async {
      server.onToken = (_) async => oauthError("invalid_grant",
          description: "Invalid user credentials", status: 401);

      await expectLater(
          _within(Auth().login("user", "wrong")),
          throwsA(isA<AuthException>()
              .having((e) => e.message, "message", Auth.invalidCredentials)));

      expect(Auth().loggedIn, isFalse);
      expect(storedToken(), isNull);
    });
  });

  group("a refresh", () {
    test("replaces the stored credentials", () async {
      await start("expired", validFor: expired);

      final headers = await _within(Auth().getHeaders());

      expect(headers["authorization"], "Bearer refreshed");
      expect(storedToken(), "refreshed");
      final request = server.tokenHttpRequests.single;
      expect(request.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains("authorization")));
      expect(request.bodyFields, {
        "grant_type": "refresh_token",
        "refresh_token": "refresh-expired",
        "client_id": dotenv.env["KEYCLOAK_CLIENTID"],
        "scope": "offline_access openid profile email",
      });
    });

    test("refused with invalid_grant logs out", () async {
      await start("expired", validFor: expired);
      server.onToken = (_) async =>
          oauthError("invalid_grant", description: "Token is not active");

      expect(await _within(Auth().getHeaders()), isEmpty);

      expect(Auth().loggedIn, isFalse);
      // The deletion follows the signed-out mark, a write to Settings.
      await _until(() => storedToken() == null);
      expect(storedToken(), isNull);
      await expectLater(Auth().getHeaders(), throwsA(isA<AuthException>()));
    });

    final failures = <(String, void Function(FakeAuthServer))>[
      ("a broken connection",
          (s) => s.tokenError = const SocketException("connection reset")),
      ("a timeout", (s) => s.holdToken = Completer<void>()),
      ("a 503", (s) => s.onToken = (_) async => http.Response("", 503)),
      ("a 502 from the ingress",
          (s) => s.onToken = (_) async => http.Response("<html>", 502)),
      ("another OAuth error",
          (s) => s.onToken =
              (_) async => oauthError("invalid_client", status: 401)),
      ("an answer that holds no token",
          (s) => s.onToken = (_) async => http.Response("<html>", 200,
              headers: {"content-type": "text/html"})),
    ];
    test("refused with invalid_grant after its bound logs out, also when the "
        "cleanup fails", () async {
      await start("expired", validFor: expired);
      final refused = Completer<void>();
      server.onToken = (_) async {
        await refused.future;
        return oauthError("invalid_grant", description: "Token is not active");
      };
      expect(await _within(Auth().getHeaders()), isEmpty);
      expect(Auth().loggedIn, isTrue, reason: "ran into its bound");
      final paths = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _FailingPathProvider();
      addTearDown(() => PathProviderPlatform.instance = paths);

      refused.complete();
      await _until(() => storedToken() == null);

      expect(Auth().loggedIn, isFalse);
      expect(Auth().tokenValid, isFalse);
      expect(storedToken(), isNull);
      await expectLater(Auth().getHeaders(), throwsA(isA<AuthException>()));
    });

    for (final (cause, fail) in failures) {
      test("that fails with $cause keeps the session", () async {
        await start("expired", validFor: expired);
        fail(server);

        expect(await _within(Auth().getHeaders()), isEmpty);
        await pumpEventQueue();

        expect(Auth().loggedIn, isTrue);
        expect(storedToken(), "expired");
        expect(store.stored!.refreshToken, "refresh-expired");
        expect(Settings.getAccount(), "test-account");
      });
    }
  });

  group("the stored credentials", () {
    test("sign in at a start without network, without a request", () async {
      server.discoveryError = const SocketException("no network");
      server.tokenError = const SocketException("no network");

      await start("stored");
      final headers = await _within(Auth().getHeaders());

      expect(Auth().loggedIn, isTrue);
      expect(headers["authorization"], "Bearer stored");
      expect(server.requests, isEmpty);
    });

    test("that cannot be read are not deleted, and the next call reads again",
        () async {
      store.put(credentials("stored"));
      legacy.put("old");
      final before = Map.of(store.data);
      store.readFails = true;

      await _within(Auth().init());

      expect(Auth().isInitialized, isTrue);
      expect(Auth().loggedIn, isFalse);
      await expectLater(Auth().getHeaders(), throwsA(isA<AuthException>()));
      await pumpEventQueue();
      expect(store.data, before);
      expect(legacy.values, isNotEmpty);
      expect(log, isEmpty, reason: "nothing written or deleted");

      store.readFails = false;
      final headers = await _within(Auth().getHeaders());

      expect(headers["authorization"], "Bearer stored");
      expect(Auth().loggedIn, isTrue);
    });

    test("that could not be read are read again when the app resumes",
        () async {
      store.put(credentials("stored"));
      store.readFails = true;
      await _within(Auth().init());
      var notified = 0;
      void count() => notified++;
      Auth().addListener(count);
      addTearDown(() => Auth().removeListener(count));

      store.readFails = false;
      Auth().didChangeAppLifecycleState(AppLifecycleState.resumed);
      await _until(() => Auth().loggedIn);

      expect(Auth().loggedIn, isTrue);
      expect(notified, greaterThan(0), reason: "the login screen gives way");
    });
  });

  group("a storage that answers nothing although credentials were stored", () {
    test("is read again, and nothing is deleted or moved", () async {
      store.put(credentials("stored"));
      await Settings.setCredentialsStored(true);
      legacy.put("old");
      final before = Map.of(store.data);
      final legacyBefore = Map.of(legacy.values);
      store.readsNil = true;

      await _within(Auth().init());

      expect(Auth().loggedIn, isFalse);
      await expectLater(Auth().getHeaders(), throwsA(isA<AuthException>()));
      await pumpEventQueue();
      expect(store.data, before);
      expect(legacy.values, legacyBefore);
      expect(log, isEmpty, reason: "nothing written or deleted");
      expect(Settings.getCredentialsStored(), isTrue);

      store.readsNil = false;
      final headers = await _within(Auth().getHeaders());

      expect(headers["authorization"], "Bearer stored");
      expect(Auth().loggedIn, isTrue);
    });

    test("is not mistaken for it after a migration and a logout", () async {
      legacy.put("old",
          expiresAt: DateTime.now().subtract(const Duration(minutes: 1)));
      await _within(Auth().init());
      expect(Settings.getCredentialsStored(), isTrue,
          reason: "set once the migration stored the credentials");
      server.onToken = (_) async =>
          oauthError("invalid_grant", description: "Token is not active");

      expect(await _within(Auth().getHeaders()), isEmpty);
      await _until(() => !Settings.getCredentialsStored());

      expect(storedToken(), isNull);
      expect(Settings.getCredentialsStored(), isFalse);
    });
  });

  group("a logout", () {
    test("in local mode with the platform reachable revokes and cleans up",
        () async {
      await start("valid");
      await Settings.setLocalMode(true);
      addTearDown(() => Settings.setLocalMode(false));
      final epoch = AccountEpoch.current;

      await _within(Auth().logout(_GoneContext()));

      expect(Auth().loggedIn, isFalse);
      expect(storedToken(), isNull);
      expect(server.revocations.single["token"], "refresh-valid");
      expect(AccountEpoch.current, isNot(epoch), reason: "the full cleanup ran");
    });

    final withoutRevocation = <(String, Future<void> Function())>[
      ("while the platform is unreachable", () async {
        await start("valid");
        ApiAvailableService.setUnreachableForTest(true);
      }),
      ("whose revocation finds no auth server", () async {
        await start("valid");
        server.discoveryError = const SocketException("no network");
      }),
      ("without readable credentials and network", () async {
        await start("valid");
        await Auth().resetForTest();
        store.readFails = true;
        Auth().loggedIn = true;
        Auth.serverAvailableOverride = () async => false;
      }),
    ];
    for (final (situation, prepare) in withoutRevocation) {
      test("$situation deletes the live certificate, the cache and the stored "
          "credentials", () async {
        final certificate = [
          ClientCertificates.keyKeyOf("test-account"),
          ClientCertificates.certKeyOf("test-account"),
        ];
        for (final key in certificate) {
          store.data[key] = "pem";
        }
        final cache = HiveCacheStore(await CacheHelper.getCacheFile());
        await cache.set(_cached("cached-request"));
        await prepare();
        final epoch = AccountEpoch.current;

        await _within(Auth().logout(_GoneContext()));

        expect(Auth().loggedIn, isFalse);
        expect(store.data.keys, isNot(contains(credentialsKey)));
        for (final key in certificate) {
          expect(store.data.keys, isNot(contains(key)),
              reason: "it would log into the broker as this user");
        }
        expect(await cache.exists("cached-request"), isFalse);
        expect(AccountEpoch.current, isNot(epoch));
        expect(Settings.getCredentialsStored(), isFalse);
        expect(server.revocations, isEmpty);
      });
    }
  });

  group("a refresh request that hangs", () {
    var now = Duration.zero;
    // One answer per token request, completed by the test.
    late List<Completer<http.Response>> answers;
    // The headers of the second refresh.
    late Future<Map<String, String>> headers;

    setUp(() {
      now = Duration.zero;
      Auth.monotonicNow = () => now;
      answers = [];
      server.onToken = (_) {
        final answer = Completer<http.Response>();
        answers.add(answer);
        return answer.future;
      };
    });

    /// A first refresh that runs into its bound and goes on.
    Future<void> hang() async {
      await start("expired", validFor: expired);
      expect(await _within(Auth().getHeaders()), isEmpty);
      expect(answers, hasLength(1));
    }

    /// A second refresh of the same credentials, once the first is older
    /// than the login bound.
    Future<void> replace() async {
      now += Auth.loginTimeout;
      Auth.tokenRefreshTimeout = const Duration(seconds: 2);
      headers = Auth().getHeaders();
      await _until(() => answers.length == 2);
      expect(answers, hasLength(2), reason: "a new request went out");
    }

    test("is joined within the login bound, and replaced past it", () async {
      await hang();

      expect(await _within(Auth().getHeaders()), isEmpty);
      expect(answers, hasLength(1), reason: "no second use of the token");

      await replace();
      answers[1].complete(tokens("refreshed"));

      expect((await _within(headers))["authorization"], "Bearer refreshed");
      expect(storedToken(), "refreshed");
      expect(server.tokenRequests.map((r) => r["refresh_token"]),
          ["refresh-expired", "refresh-expired"]);
    });

    test("that ends with invalid_grant after its replacement stored new "
        "tokens is dropped", () async {
      await hang();
      await replace();
      answers[1].complete(tokens("rotated"));
      expect((await _within(headers))["authorization"], "Bearer rotated");

      answers[0].complete(
          oauthError("invalid_grant", description: "Token is not active"));
      await pumpEventQueue();

      expect(Auth().loggedIn, isTrue);
      expect(storedToken(), "rotated");
    });

    test("that ends with invalid_grant while its replacement runs leaves the "
        "outcome to that one", () async {
      await hang();
      await replace();

      answers[0].complete(
          oauthError("invalid_grant", description: "Token is not active"));
      await pumpEventQueue();
      expect(Auth().loggedIn, isTrue);

      answers[1].complete(tokens("rotated"));
      expect((await _within(headers))["authorization"], "Bearer rotated");
      expect(storedToken(), "rotated");
    });

    test("that succeeds after its replacement failed is applied", () async {
      await hang();
      await replace();
      answers[1].complete(http.Response("", 503));
      expect(await _within(headers), isEmpty);

      answers[0].complete(tokens("late"));
      await _until(() => storedToken() == "late");

      expect(storedToken(), "late");
      expect(Auth().loggedIn, isTrue);
      expect((await _within(Auth().getHeaders()))["authorization"],
          "Bearer late");
    });
  });

  group("a logout whose deletion did not take", () {
    late _UndeletableStore undeletable;

    setUp(() {
      undeletable = _UndeletableStore(log);
      store = undeletable..install();
    });

    Future<void> logOutAndRestart() async {
      await start("valid");
      await _within(Auth().onLogoutForTest());
      expect(Auth().loggedIn, isFalse);
      expect(storedToken(), "valid", reason: "the deletion did not take");
      await Auth().resetForTest();
      await _within(Auth().init());
    }

    test("because it failed does not sign in at the next start, which "
        "deletes again", () async {
      undeletable.deleteFails = true;

      await logOutAndRestart();

      expect(Auth().loggedIn, isFalse);
      await expectLater(Auth().getHeaders(), throwsA(isA<AuthException>()));
      undeletable.deleteFails = false;
      await Auth().resetForTest();
      await _within(Auth().init());
      await _until(() => storedToken() == null);
      expect(storedToken(), isNull);
      expect(Auth().loggedIn, isFalse);
    });

    test("although reported done does not sign in at the next start",
        () async {
      undeletable.deletesNothing = true;

      await logOutAndRestart();

      expect(Auth().loggedIn, isFalse);
      await pumpEventQueue();
      expect(undeletable.deletions, 2, reason: "deleted again at the start");
    });

    test("does not keep a later login from the next start", () async {
      undeletable.deleteFails = true;
      await logOutAndRestart();

      await _within(Auth().login("user", "pw"));
      await Auth().resetForTest();
      await _within(Auth().init());

      expect(Auth().loggedIn, isTrue);
      expect((await _within(Auth().getHeaders()))["authorization"],
          "Bearer signed-in");
    });
  });

  test("a login fails within its bound while the cleanup of the last logout "
      "hangs", () async {
    await start("valid");
    final paths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _HangingPathProvider();
    addTearDown(() => PathProviderPlatform.instance = paths);
    unawaited(Auth().onLogoutForTest());
    Auth.loginTimeout = _bound;

    await expectLater(
        _within(Auth().login("user", "pw")),
        throwsA(isA<AuthException>()
            .having((e) => e.message, "message", "Can't login, are you online?")));

    expect(Auth().loggingIn, isFalse);
    expect(Auth().loggedIn, isFalse);
  });

  group("a live certificate request whose headers need a refresh", () {
    final headers = ClientCertificates.headers;
    final apiUrl = ClientCertificates.apiUrl;
    final device = ClientCertificates.device;
    final dio = ClientCertificates.dio;

    setUp(() {
      // The production headers: from Auth, under the certificate lock.
      ClientCertificates.headers = () => Auth().getHeaders();
      ClientCertificates.apiUrl = () => "https://api.test";
      ClientCertificates.device = () async => ("Google", "Pixel 7");
      final client = Dio()..httpClientAdapter = FakeBackend();
      ClientCertificates.dio = () async => client;
    });

    tearDown(() async {
      ClientCertificates.headers = headers;
      ClientCertificates.apiUrl = apiUrl;
      ClientCertificates.device = device;
      ClientCertificates.dio = dio;
      await Settings.setAccountWipePending(false);
    });

    test("ends when Keycloak refuses the refresh, and the logout follows",
        () async {
      await start("expired", validFor: expired);
      server.onToken = (_) async =>
          oauthError("invalid_grant", description: "Token is not active");

      await _within(ClientCertificates.current());

      expect(Auth().loggedIn, isFalse);
      await expectLater(Auth().getHeaders(), throwsA(isA<AuthException>()));
      await _until(() => storedToken() == null);
      expect(storedToken(), isNull);
    });

    test("ends when the refresh retries a pending account wipe, and the wipe "
        "follows", () async {
      await start("expired", validFor: expired);
      await Settings.setAccountWipePending(true);

      await _within(ClientCertificates.current());

      expect(Auth().loggedIn, isTrue);
      await _until(() => !Settings.getAccountWipePending());
      expect(Settings.getAccountWipePending(), isFalse);
      expect(storedToken(), "refreshed");
    });
  });

  group("the migration", () {
    test("moves the previous identity and deletes it only after", () async {
      legacy.put("old", sub: "account-a");

      await _within(Auth().init());
      await _until(() => legacy.values.isEmpty);

      expect(Auth().loggedIn, isTrue);
      expect(Settings.getAccount(), "account-a");
      expect(Auth().getUsername(), "user-account-a");
      expect(storedToken(), "old");
      expect(store.stored!.refreshToken, "refresh-old");
      expect(legacy.values, isEmpty);
      expect(store.data[migratedKey], isNotNull);
      final firstLegacyDelete =
          log.indexWhere((e) => e.startsWith("legacy delete"));
      expect(firstLegacyDelete, greaterThan(log.indexOf("write $credentialsKey")),
          reason: "the previous values go only once the new ones are stored");
    });

    test("completes the token endpoint at the first refresh", () async {
      legacy.put("old",
          expiresAt: DateTime.now().subtract(const Duration(minutes: 1)));
      await _within(Auth().init());
      expect(store.stored!.tokenEndpoint, isNull);

      final headers = await _within(Auth().getHeaders());

      expect(headers["authorization"], "Bearer refreshed");
      expect(server.discoveries, 1);
      expect(server.tokenRequests.single["refresh_token"], "refresh-old");
      expect(store.stored!.tokenEndpoint, tokenEndpoint);
    });

    test("that cannot read the previous identity leaves it and marks nothing",
        () async {
      legacy.put("old");
      final before = Map.of(legacy.values);
      legacy.readFails = true;

      await _within(Auth().init());

      expect(Auth().loggedIn, isFalse);
      expect(legacy.values, before);
      expect(log, isEmpty, reason: "nothing written or deleted");

      // Later, as after the unlock.
      legacy.readFails = false;
      final headers = await _within(Auth().getHeaders());
      await _until(() => legacy.values.isEmpty);

      expect(headers["authorization"], "Bearer old");
      expect(storedToken(), "old");
      expect(legacy.values, isEmpty);
    });

    test("that cannot store the credentials keeps the previous identity for "
        "the next start", () async {
      legacy.put("old");
      final before = Map.of(legacy.values);
      store.writeFails = true;

      await _within(Auth().init());
      await pumpEventQueue();

      expect(Auth().loggedIn, isTrue, reason: "signed in for this run");
      expect(legacy.values, before);
      expect(store.data[migratedKey], isNull);

      // The next start.
      await Auth().resetForTest();
      store.writeFails = false;
      await _within(Auth().init());
      await _until(() => legacy.values.isEmpty);

      expect(storedToken(), "old");
      expect(legacy.values, isEmpty);
    });

    test("does not move an identity left behind after a logout", () async {
      legacy.put("old", sub: "account-a");
      await _within(Auth().init());
      Auth.serverAvailableOverride = () async => false;
      await Auth().onLogoutForTest();
      // A deletion that did not take.
      legacy.put("old", sub: "account-a");

      // The next start.
      await Auth().resetForTest();
      await _within(Auth().init());

      expect(Auth().loggedIn, isFalse);
      expect(storedToken(), isNull);
    });
  });
}
