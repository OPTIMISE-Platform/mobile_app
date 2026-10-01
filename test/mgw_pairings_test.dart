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

import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_command.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/device_commands.dart';
import 'package:mobile_app/services/mgw/auth_service.dart';
import 'package:mobile_app/services/mgw/reachability.dart';
import 'package:mobile_app/services/mgw/restricted.dart';
import 'package:mobile_app/services/mgw/storage.dart';
import 'package:mobile_app/shared/http_client_adapter.dart';
import 'package:mobile_app/widgets/tabs/gateways/mgw_page.dart';

import 'golden_helper.dart';

const _endpoints = "/core/api/core-manager/endpoints";
const _batch = "/mgw-dc/commands/batch";
const _expires = "2099-01-01T00:00:00Z";

ResponseBody _json(int status, Object body) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });

/// Gateways by URI host, each issuing and accepting its own login. A session
/// token is valid at a gateway only when that gateway issued it.
class _Gateways implements HttpClientAdapter {
  _Gateways(this.logins);

  /// URI host -> the login the gateway issues when paired and accepts after.
  final Map<String, String> logins;
  final List<RequestOptions> requests = [];

  static String tokenOf(String login) => "token-$login";

  /// Logins sent to [host]'s identity provider.
  List<String> loginsSentTo(String host) => [
        for (final r in requests)
          if (r.uri.host == host && r.uri.path == "/core/auth/login")
            jsonDecode(r.data as String)["identifier"] as String
      ];

  List<RequestOptions> to(String host, String path) => requests
      .where((r) => r.uri.host == host && r.uri.path == path)
      .toList();

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final login = logins[options.uri.host];
    if (login == null) {
      throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: const SocketException("Connection refused"));
    }
    final valid = options.headers["X-Session-Token"] == tokenOf(login);
    switch (options.uri.path) {
      case "/":
        return ResponseBody.fromString("", 200);
      case "/core/api/auth-service/pairing/request":
        return _json(200, {"id": "id-$login", "login": login, "secret": "s"});
      case "/core/auth/login/api":
        return _json(200, {"id": "flow-1"});
      case "/core/auth/login":
        final sent = jsonDecode(options.data as String)["identifier"];
        if (sent != login) {
          return _json(400, {
            "error": {"code": 400, "reason": "the provided credentials are invalid"}
          });
        }
        return _json(200, {
          "session_token": tokenOf(login),
          "session": {"expires_at": _expires}
        });
      case _endpoints:
        return valid
            ? _json(200, {
                "endpoint-1": {"id": "endpoint-1", "location": "/mgw-dc", "ref": "r"}
              })
            : ResponseBody.fromString("unknown session", 401);
      case _batch:
        return valid
            ? _json(200, [
                {"status_code": 200, "message": "done by $login"}
              ])
            : ResponseBody.fromString("unknown session", 401);
    }
    return ResponseBody.fromString("", 404);
  }

  @override
  void close({bool force = false}) {}
}

/// Secure storage whose entries under [writeFails] throw on write, like a
/// Keystore that is briefly unavailable; keys matching [storedThenFails] are
/// written and the write still reports failure.
class _FailingStore extends MapBase<String, String> {
  final writeFails = <String>{};
  bool Function(String key) storedThenFails = (_) => false;
  final _inner = <String, String>{};

  static Never _fail() => throw PlatformException(code: "KeystoreUnavailable");

  @override
  String? operator [](Object? key) => _inner[key];

  @override
  void operator []=(String key, String value) {
    if (writeFails.contains(key)) _fail();
    _inner[key] = value;
    if (storedThenFails(key)) _fail();
  }

  @override
  String? remove(Object? key) => _inner.remove(key);

  @override
  void clear() => _inner.clear();

  @override
  Iterable<String> get keys => _inner.keys;
}

const _secure = FlutterSecureStorage();

Future<String?> _read(String key) => _secure.read(key: key);

Future<String?> _session(MGW mgw) =>
    _read(MgwService.sessionKeyOf(mgw.pairingId));

Future<String> _login(MGW mgw) async =>
    (await MgwStorage.LoadCredentials(mgw.pairingId)).login;

Future<void> _storeSession(MGW mgw, String token) async {
  await _secure.write(key: MgwService.sessionKeyOf(mgw.pairingId), value: token);
  await _secure.write(
      key: MgwService.sessionExpirationKeyOf(mgw.pairingId), value: _expires);
}

/// Writes the list as an app version before pairing ids stored it.
Future<void> _storeWithoutIds(List<MGW> mgws) => Hive.box<String>("mgw.box")
    .put("connected_mgws_", jsonEncode([
      for (final m in mgws)
        {
          "hostname": m.hostname,
          "mDNSServiceName": m.mDNSServiceName,
          "coreId": m.coreId,
          "ip": m.ip,
          "networkId": m.networkId,
        }
    ]));

const _sharedCredentials = "mgw-device-credentials";
const _sharedSession = "mgw-session";
const _sharedExpiration = "mgw-session-expiration";

String _credentialsJson(String login) =>
    jsonEncode(DeviceUserCredentials("id-$login", login, "s"));

void main() {
  late Map<String, String> store;

  setUpAll(() async {
    await setUpGoldenEnvironment();
    await MgwStorage.init();
    // The constructor starts a discovery of its own; let it end first.
    AppState();
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });

  setUp(() async {
    store = {};
    FlutterSecureStorage.setMockInitialValues(store);
    await MgwStorage.ReplacePairedMGWs([]);
    MgwStorage.restartForTest();
  });

  tearDown(() async {
    AppHttpClientAdapter.testOverride = null;
    Auth.headersOverride = null;
    MgwStorage.beforeListWriteForTest = null;
    MgwReachability.probeOverride = null;
    MgwReachability.forget();
    await MgwStorage.ReplacePairedMGWs([]);
    resetAppStateForGolden();
  });

  group("two pairings", () {
    const hostA = "192.0.2.10";
    const hostB = "192.0.2.20";
    late _Gateways gateways;

    setUp(() {
      gateways = _Gateways({hostA: "login-a", hostB: "login-b"});
      AppHttpClientAdapter.testOverride = gateways;
    });

    test("pairing a second gateway leaves the first one's credentials and "
        "session, and each check logs in with its own", () async {
      final a = await PairWithGateway(
          MGW(hostA, "A", "", "$hostA:8081", networkId: "n1"));
      expect((await MgwReachability.check(a, force: true)).status,
          MgwStatus.ok);
      expect(await _session(a), _Gateways.tokenOf("login-a"));

      final b = await PairWithGateway(
          MGW(hostB, "B", "", hostB, networkId: "n2"));

      expect(b.pairingId, isNot(a.pairingId));
      expect(await _login(a), "login-a");
      expect(await _session(a), _Gateways.tokenOf("login-a"));
      expect(await _login(b), "login-b");

      final reportA = await MgwReachability.check(a, force: true);
      final reportB = await MgwReachability.check(b, force: true);
      expect(reportA.status, MgwStatus.ok);
      expect(reportA.sessionReused, isTrue,
          reason: "A's session survived pairing B");
      expect(reportB.status, MgwStatus.ok);
      expect(gateways.loginsSentTo(hostA), ["login-a"]);
      expect(gateways.loginsSentTo(hostB), ["login-b"]);
    });

    test("removing one pairing leaves the other's secrets", () async {
      final a = await PairWithGateway(MGW(hostA, "A", "", hostA, networkId: "n1"));
      final b = await PairWithGateway(MGW(hostB, "B", "", hostB, networkId: "n2"));
      await _storeSession(a, "session-a");
      await _storeSession(b, "session-b");

      expect(await MgwStorage.RemovePairedMGW(a), isTrue);

      await expectLater(MgwStorage.LoadCredentials(a.pairingId),
          throwsA(isA<MgwCredentialsMissing>()));
      expect(await _session(a), isNull);
      expect(await _login(b), "login-b");
      expect(await _session(b), "session-b");
      expect(
          await _read(MgwService.sessionExpirationKeyOf(b.pairingId)), _expires);
    });

    test("the 401 retry for one gateway does not drop the other's session",
        () async {
      final a = await PairWithGateway(MGW(hostA, "A", "", hostA, networkId: "n1"));
      final b = await PairWithGateway(MGW(hostB, "B", "", hostB, networkId: "n2"));
      await _storeSession(a, "stale-a");
      await _storeSession(b, _Gateways.tokenOf("login-b"));

      final report = await MgwReachability.check(a, force: true);

      expect(report.status, MgwStatus.ok);
      expect(report.retriedWithFreshLogin, isTrue);
      expect(await _session(a), _Gateways.tokenOf("login-a"));
      expect(await _session(b), _Gateways.tokenOf("login-b"));
    });
  });

  group("migration of the shared credentials", () {
    final a = MGW("a.local", "A", "c1", "10.0.0.1", networkId: "n1");
    final b = MGW("b.local", "B", "c2", "10.0.0.2", networkId: "n2");

    Future<void> storeShared({bool withSession = true}) async {
      store[_sharedCredentials] = _credentialsJson("shared");
      if (withSession) {
        store[_sharedSession] = "shared-session";
        store[_sharedExpiration] = _expires;
      }
    }

    test("entries stored without a pairing id get one once", () async {
      await _storeWithoutIds([a, b]);

      final first = await MgwStorage.LoadPairedMGWs();
      final second = await MgwStorage.LoadPairedMGWs();

      expect(first.map((m) => m.pairingId), everyElement(isNotEmpty));
      expect(first[0].pairingId, isNot(first[1].pairingId));
      expect(second.map((m) => m.pairingId), first.map((m) => m.pairingId));
      expect(Hive.box<String>("mgw.box").get("connected_mgws_"),
          contains(first[0].pairingId));
    });

    test("one entry keeps working with the shared credentials and session",
        () async {
      await _storeWithoutIds([MGW("192.0.2.30", "A", "", "192.0.2.30")]);
      store[_sharedCredentials] = _credentialsJson("login-a");
      store[_sharedSession] = _Gateways.tokenOf("login-a");
      store[_sharedExpiration] = _expires;
      final gateways = _Gateways({"192.0.2.30": "login-a"});
      AppHttpClientAdapter.testOverride = gateways;

      final entry = (await MgwStorage.LoadPairedMGWs()).single;
      final report = await MgwReachability.check(entry, force: true);

      expect(report.status, MgwStatus.ok);
      expect(report.sessionReused, isTrue);
      expect(gateways.loginsSentTo("192.0.2.30"), isEmpty);
      expect(await _login(entry), "login-a");
      expect(store.keys,
          isNot(anyOf(contains(_sharedCredentials), contains(_sharedSession),
              contains(_sharedExpiration))));
    });

    test("two entries each get a copy, then the shared keys go", () async {
      await _storeWithoutIds([a, b]);
      await storeShared();

      final stored = await MgwStorage.LoadPairedMGWs();
      for (final m in stored) {
        expect(await _login(m), "shared");
        expect(await _session(m), "shared-session");
      }
      expect(store.containsKey(_sharedCredentials), isFalse);
      expect(store.containsKey(_sharedSession), isFalse);
      expect(store.containsKey(_sharedExpiration), isFalse);
    });

    test("the plaintext key of older versions is migrated the same way",
        () async {
      await _storeWithoutIds([a]);
      await Hive.box<String>("mgw.box")
          .put("credentials_", _credentialsJson("from-hive"));

      final entry = (await MgwStorage.LoadPairedMGWs()).single;

      expect(await _login(entry), "from-hive");
      expect(Hive.box<String>("mgw.box").get("credentials_"), isNull);
    });

    test("a failed copy keeps the shared key, and the next start finishes "
        "without touching what was copied or paired since", () async {
      await _storeWithoutIds([a, b]);
      final [first, second] = await MgwStorage.LoadPairedMGWs();
      final failing = _FailingStore()
        ..[_sharedCredentials] = _credentialsJson("shared")
        ..writeFails.add(MgwStorage.credentialsKeyOf(second.pairingId));
      FlutterSecureStorage.setMockInitialValues(failing);

      expect(await _login(first), "shared");
      await expectLater(MgwStorage.LoadCredentials(second.pairingId),
          throwsA(isA<PlatformException>()),
          reason: "a store that failed is not reported as no pairing");
      expect(failing.containsKey(_sharedCredentials), isTrue);

      // The first gateway is paired again before the next start.
      failing[MgwStorage.credentialsKeyOf(first.pairingId)] =
          _credentialsJson("re-paired");
      failing.writeFails.clear();
      MgwStorage.restartForTest();

      expect(await _login(second), "shared");
      expect(await _login(first), "re-paired");
      expect(failing.containsKey(_sharedCredentials), isFalse);
    });

    test("a session copy that failed is made again on the next start",
        () async {
      await _storeWithoutIds([a, b]);
      final [first, second] = await MgwStorage.LoadPairedMGWs();
      final failing = _FailingStore()
        ..[_sharedCredentials] = _credentialsJson("shared")
        ..[_sharedSession] = "shared-session"
        ..[_sharedExpiration] = _expires
        ..writeFails.add(MgwService.sessionKeyOf(second.pairingId));
      FlutterSecureStorage.setMockInitialValues(failing);
      expect(await _login(first), "shared");

      failing.writeFails.clear();
      MgwStorage.restartForTest();

      expect(await _login(second), "shared");
      expect(await _session(second), "shared-session",
          reason: "an entry counts as done only once it has credentials");
    });

    test("a second start after the migration changes nothing", () async {
      await _storeWithoutIds([a, b]);
      await storeShared();
      final [first, second] = await MgwStorage.LoadPairedMGWs();
      expect(await _login(first), "shared");
      // Paired again between the two starts.
      await MgwStorage.StoreCredentials(
          first.pairingId, DeviceUserCredentials("id", "re-paired", "s"));
      await _storeSession(first, "session-re-paired");
      final afterFirst = Map.of(store);

      MgwStorage.restartForTest();
      expect(await _login(second), "shared");

      expect(store, afterFirst);
      expect(await _login(first), "re-paired");
    });

    test("removing the last entry before the migration drops the shared keys",
        () async {
      await _storeWithoutIds([a]);
      await storeShared();

      expect(await MgwStorage.RemovePairedMGW(a), isTrue);

      expect(store, isEmpty);
    });
  });

  group("pairing ids", () {
    test("stay the same when the same gateway is stored again", () async {
      final first = await MgwStorage.StorePairedMGW(
          MGW("mgw.local", "MGW", "c1", "192.168.1.5", networkId: "n1"));
      final again = await MgwStorage.StorePairedMGW(
          MGW("mgw.local", "MGW", "c1", "192.168.1.9", networkId: "n1"));

      expect(again.pairingId, first.pairingId);
      expect((await MgwStorage.LoadPairedMGWs()).single.pairingId,
          first.pairingId);
    });

    test("stay the same when pairing again binds to another network",
        () async {
      AppHttpClientAdapter.testOverride = _Gateways({"10.0.0.1": "login-2"});
      final old = await MgwStorage.StorePairedMGW(
          MGW("10.0.0.1", "10.0.0.1", "", "10.0.0.1", networkId: "n1"),
          credentials: DeviceUserCredentials("id-1", "login-1", "s"));
      await _storeSession(old, "session-1");

      final stored = await PairWithGateway(
          MGW(old.hostname, old.mDNSServiceName, old.coreId, old.ip,
              networkId: "n2"),
          replacing: old);

      expect(stored.pairingId, old.pairingId);
      expect(stored.networkId, "n2");
      expect(await _login(stored), "login-2");
      expect(await _session(stored), isNull,
          reason: "the session of the replaced credentials is dropped");
    });

    test("collapsing a duplicate keeps the first id and drops the "
        "duplicate's secrets", () async {
      final kept = MGW("a.local", "A", "c1", "10.0.0.1", pairingId: "p1");
      final duplicate = MGW("a.local", "A", "c1", "10.0.0.1", pairingId: "p2");
      final other = MGW("b.local", "B", "c2", "10.0.0.2", pairingId: "p3");
      await MgwStorage.ReplacePairedMGWs([kept, duplicate, other]);
      for (final m in [kept, duplicate, other]) {
        await MgwStorage.StoreCredentials(
            m.pairingId, DeviceUserCredentials("id", m.pairingId, "s"));
        await _storeSession(m, "session-${m.pairingId}");
      }

      final stored = await MgwStorage.StorePairedMGW(
          MGW("a.local", "A", "c1", "10.0.0.3"));

      expect(stored.pairingId, "p1");
      expect((await MgwStorage.LoadPairedMGWs()).map((m) => m.pairingId),
          ["p1", "p3"]);
      expect(await _login(kept), "p1");
      expect(await _session(kept), "session-p1");
      expect(await _login(other), "p3");
      expect(store.containsKey(MgwStorage.credentialsKeyOf("p2")), isFalse);
      expect(await _session(duplicate), isNull);
    });
  });

  group("a pairing that fails after the gateway issued credentials", () {
    test("drops credentials whose write reported a failure", () async {
      final failing = _FailingStore()
        ..storedThenFails = (key) => key.startsWith("$_sharedCredentials:");
      FlutterSecureStorage.setMockInitialValues(failing);

      await expectLater(
          MgwStorage.StorePairedMGW(
              MGW("10.0.0.7", "10.0.0.7", "", "10.0.0.7", networkId: "n1"),
              credentials: DeviceUserCredentials("id", "login-new", "s")),
          throwsA(isA<PlatformException>()));

      expect(failing.keys.where((k) => k.startsWith("$_sharedCredentials:")),
          isEmpty);
      expect(await MgwStorage.LoadPairedMGWs(), isEmpty);
    });

    test("leaves no credentials under an id no entry carries", () async {
      final existing = await MgwStorage.StorePairedMGW(
          MGW("b.local", "B", "c2", "10.0.0.2", networkId: "n2"),
          credentials: DeviceUserCredentials("id-b", "login-b", "s"));
      AppHttpClientAdapter.testOverride = _Gateways({"10.0.0.7": "login-new"});
      MgwStorage.beforeListWriteForTest =
          () => throw HiveError("the box cannot be written");

      final result = await pairAndStore(
          MGW("10.0.0.7", "10.0.0.7", "", "10.0.0.7", networkId: "n1"),
          AppState());

      expect(result.failure, isNotNull);
      MgwStorage.beforeListWriteForTest = null;
      final stored = await MgwStorage.LoadPairedMGWs();
      expect(stored.map((m) => m.pairingId), [existing.pairingId]);
      expect(
          store.keys.where((k) => k.startsWith("$_sharedCredentials:")),
          [MgwStorage.credentialsKeyOf(existing.pairingId)]);
      expect(await _login(existing), "login-b");
    });
  });

  test("a command goes out with the credentials of the entry routed for its "
      "network when two entries share an address", () async {
    // Two homes with their gateway at the same router address; only the one
    // in this network answers.
    final office = MGW("192.168.0.2", "Office", "", "192.168.0.2",
        networkId: "network-office");
    final home = MGW("192.168.0.2", "Home", "", "192.168.0.2",
        networkId: "network-home");
    await MgwStorage.ReplacePairedMGWs([office, home]);
    await MgwStorage.StoreCredentials(
        office.pairingId, DeviceUserCredentials("id", "login-office", "s"));
    await MgwStorage.StoreCredentials(
        home.pairingId, DeviceUserCredentials("id", "login-home", "s"));
    final gateways = _Gateways({"192.168.0.2": "login-home"});
    AppHttpClientAdapter.testOverride = gateways;
    Auth.headersOverride = () async => {"authorization": "Bearer t"};
    MgwReachability.probeOverride = (mgw) async => MgwReport(
        status: mgw.networkId == "network-home"
            ? MgwStatus.ok
            : MgwStatus.foreign,
        address: mgw.ip,
        checkedAt: DateTime.utc(2026));
    AppState().networks.addAll([
      Network("network-office", "Office", false, ["office-local"], ["office"],
          DeviceConnectionStatus.online, "", "owner-1"),
      Network("network-home", "Home", false, ["lamp-local"], ["lamp"],
          DeviceConnectionStatus.online, "", "owner-1"),
    ]);
    await AppState().mergeGatewaysWithNetworks();
    final lamp = DeviceInstance("lamp", "lamp-local", "Lamp", null,
        "device-type-1", false, "owner-1", "Lamp",
        DeviceConnectionStatus.online);
    final command = DeviceCommand("function-1", "lamp", "service-1", "aspect-1")
      ..deviceInstance = lamp;

    final result = await DeviceCommandsService.runCommands([command]);

    expect(result.single.message, "done by login-home");
    expect(gateways.loginsSentTo("192.168.0.2"), ["login-home"]);
    expect(gateways.to("192.168.0.2", _batch), hasLength(1),
        reason: "a command is sent once");
  });
}
