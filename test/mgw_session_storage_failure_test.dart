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

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_command.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/services/device_commands.dart';
import 'package:mobile_app/services/mgw/auth_service.dart';
import 'package:mobile_app/services/mgw/reachability.dart';
import 'package:mobile_app/services/mgw/restricted.dart';
import 'package:mobile_app/services/mgw/storage.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

const _credentialsKey = "mgw-device-credentials";

const _sessionKeys = {
  MgwService.sessionStorageKey,
  MgwService.sessionExpirationStorageKey,
};

/// Secure storage whose entries under [readFails] / [writeFails] throw, like a
/// Keystore that is briefly unavailable.
class _FailingStore extends MapBase<String, String> {
  final readFails = <String>{};
  final writeFails = <String>{};
  final _inner = <String, String>{};

  static Never _fail() =>
      throw PlatformException(code: "KeystoreUnavailable");

  @override
  String? operator [](Object? key) =>
      readFails.contains(key) ? _fail() : _inner[key];

  @override
  void operator []=(String key, String value) =>
      writeFails.contains(key) ? _fail() : _inner[key] = value;

  @override
  String? remove(Object? key) =>
      writeFails.contains(key) ? _fail() : _inner.remove(key);

  @override
  void clear() => _inner.clear();

  @override
  Iterable<String> get keys => _inner.keys;
}

const _gatewayEndpoints = "/core/api/core-manager/endpoints";
const _gatewayBatch = "/mgw-dc/commands/batch";
const _platformBatch = "/device-command/commands/batch";

/// Fails the test instead of hanging it when a request never returns.
const _budget = Duration(seconds: 5);

void main() {
  late FakeBackend backend;

  setUpAll(() async {
    await setUpGoldenEnvironment();
    await MgwStorage.init();
  });

  /// Stores credentials, then lets the entries under [read] and [write] fail.
  Future<void> useStore(
      {Set<String> read = const {}, Set<String> write = const {}}) async {
    final store = _FailingStore();
    FlutterSecureStorage.setMockInitialValues(store);
    await MgwStorage.StoreCredentials(DeviceUserCredentials("id", "login", "s"));
    store.readFails.addAll(read);
    store.writeFails.addAll(write);
  }

  setUp(() async {
    await useStore(read: _sessionKeys, write: _sessionKeys);
    backend = FakeBackend();
    serveGoldenBackend(backend);
  });

  tearDown(() {
    FlutterSecureStorage.setMockInitialValues({});
    MgwReachability.forget();
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  test("a probe completes and names the storage", () async {
    backend.serveJson("GET", "/", 200, "");

    final report = await MgwReachability.check("gw.test", force: true)
        .timeout(_budget);

    expect(report.status, MgwStatus.unknown);
    expect(report.failedCheck, MgwFailedCheck.sessionStorage);
    expect(backend.requests.where((r) => r.uri.path == _gatewayEndpoints),
        isEmpty);
  });

  test("a command completes and falls back to the platform", () async {
    backend.serveJson("GET", _gatewayEndpoints, 200, {
      "endpoint-1": {"id": "endpoint-1", "location": "/mgw-dc", "ref": "r"}
    });
    // Sent without a token, the gateway refuses the batch.
    backend.serveJson("POST", _gatewayBatch, 401, "no session",
        contentType: "text/plain");
    backend.serveJson("POST", _platformBatch, 200, [
      {"status_code": 200, "message": "ok"}
    ]);
    final device = DeviceInstance("B", "B-local", "B", null, "device-type-1",
        false, "owner-1", "B", DeviceConnectionStatus.online);
    AppState().networks.add(Network("network-B", "Home", false, ["B-local"],
        ["B"], DeviceConnectionStatus.online, "", "owner-1")
      ..localGatewayHosts = ["gw.test"]);
    final command = DeviceCommand("function-1", "B", "service-1", "aspect-1")
      ..deviceInstance = device;

    final result =
        await DeviceCommandsService.runCommands([command]).timeout(_budget);

    expect(backend.requests.where((r) => r.uri.path == _gatewayBatch),
        hasLength(1));
    expect(backend.requests.where((r) => r.uri.path == _platformBatch),
        hasLength(1));
    expect(result.single.status_code, 200);
  });

  test("a credential read that throws is not reported as missing", () async {
    await useStore(read: {_credentialsKey});
    backend.serveJson("GET", "/", 200, "");

    final report = await MgwReachability.check("gw.test", force: true)
        .timeout(_budget);

    expect(report.failedCheck, MgwFailedCheck.sessionStorage);
    expect(report.status, MgwStatus.unknown);
  });

  test("a session that cannot be stored is still used for the request",
      () async {
    await useStore(write: _sessionKeys);
    backend.serveJson("GET", "/", 200, "");
    backend.serveJson("GET", "/core/auth/login/api", 200, {"id": "flow-1"});
    backend.serveJson("POST", "/core/auth/login", 200, {
      "session_token": "fresh",
      "session": {"expires_at": "2099-01-01T00:00:00Z"}
    });
    backend.serveJson("GET", _gatewayEndpoints, 200, {});

    final report = await MgwReachability.check("gw.test", force: true)
        .timeout(_budget);

    expect(report.status, MgwStatus.ok);
    final sent = backend.requests.where((r) => r.uri.path == _gatewayEndpoints);
    expect(sent.single.headers["X-Session-Token"], "fresh");
  });
}
