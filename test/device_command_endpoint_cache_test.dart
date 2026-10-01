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

@Tags(['isar'])
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_command.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/mgw_deployment.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/services/device_commands.dart';
import 'package:mobile_app/services/mgw/core_manager.dart';
import 'package:mobile_app/services/mgw/device_manager_new.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';
import 'test_helper.dart';

const _gatewayEndpoints = "/core/api/core-manager/endpoints";
const _gatewayBatch = "/mgw-dc/commands/batch";
const _platformBatch = "/device-command/commands/batch";

const _commandModule = DeviceCommandPath.deviceManagerModuleName;
const _deviceModule = DeviceManagerNew.deviceManagerModuleName;

final _gatewayA = MGW("gw-a.test", "A", "", "gw-a.test",
    networkId: "network-A", pairingId: "pairing-A");
final _gatewayB = MGW("gw-b.test", "B", "", "gw-b.test",
    networkId: "network-B", pairingId: "pairing-B");

void main() {
  late Isar db;
  late FakeBackend backend;

  setUpAll(() async {
    db = await openTestIsar([EndpointSchema]);
    await setUpGoldenEnvironment();
  });

  setUp(() async {
    backend = FakeBackend();
    serveGoldenBackend(backend);
  });

  tearDown(() async {
    resetAppStateForGolden();
    resetGoldenBackend();
    await db.writeTxn(() => db.endpoints.clear());
  });

  Future<void> cache(String module, String id, String location,
          {String pairingId = ""}) =>
      db.writeTxn(() => db.endpoints.put(Endpoint(id, location, "r",
          moduleName: module, pairingId: pairingId)));

  /// A command for a device in the network [gateway] serves.
  DeviceCommand gatewayCommand(MGW gateway) {
    final name = gateway.mDNSServiceName;
    final d = DeviceInstance(name, "$name-local", name, null, "device-type-1",
        false, "owner-1", name, DeviceConnectionStatus.online);
    AppState().networks.add(Network(gateway.networkId, "Home $name", false,
        ["$name-local"], [name], DeviceConnectionStatus.online, "", "owner-1")
      ..localGateways = [gateway]);
    return DeviceCommand("function-1", name, "service-1", "aspect-1")
      ..deviceInstance = d;
  }

  Future<List<String>> cachedLocations({String? module}) async => [
        for (final e in await db.endpoints.where().findAll())
          if (module == null || e.moduleName == module)
            "${e.pairingId}${e.location}"
      ]..sort();

  List<RequestOptions> requestsTo(String path) =>
      backend.requests.where((r) => r.uri.path == path).toList();

  test("a cached endpoint is used without asking the core-manager", () async {
    await cache(_commandModule, "endpoint-b", "/mgw-dc", pairingId: "pairing-B");
    backend.serveJson("POST", _gatewayBatch, 200, [
      {"status_code": 200, "message": "done"}
    ]);

    final result =
        await DeviceCommandsService.runCommands([gatewayCommand(_gatewayB)]);

    expect(requestsTo(_gatewayEndpoints), isEmpty);
    expect(result.single.message, "done");
    expect(await cachedLocations(), ["pairing-B/mgw-dc"],
        reason: "a served batch keeps the cache");
  });

  test("each gateway's commands go to its own cached endpoint", () async {
    await cache(_commandModule, "endpoint-a", "/mgw-dc-a", pairingId: "pairing-A");
    await cache(_commandModule, "endpoint-b", "/mgw-dc-b", pairingId: "pairing-B");
    for (final path in ["/mgw-dc-a", "/mgw-dc-b"]) {
      backend.serveJson("POST", "$path/commands/batch", 200, [
        {"status_code": 200, "message": "done at $path"}
      ]);
    }

    final result = await DeviceCommandsService.runCommands(
        [gatewayCommand(_gatewayA), gatewayCommand(_gatewayB)]);

    expect(result.map((r) => r.message),
        ["done at /mgw-dc-a", "done at /mgw-dc-b"]);
    expect(requestsTo("/mgw-dc-a/commands/batch").map((r) => r.uri.host),
        ["gw-a.test"]);
    expect(requestsTo("/mgw-dc-b/commands/batch").map((r) => r.uri.host),
        ["gw-b.test"]);
    expect(requestsTo(_gatewayEndpoints), isEmpty);
  });

  test("two gateways reporting the same endpoint id keep a row each",
      () async {
    Future<void> cacheFrom(MGW gateway, String location) async {
      backend.serveJson("GET", _gatewayEndpoints, 200, {
        "endpoint-1": {"id": "endpoint-1", "location": location, "ref": "r"}
      });
      await MgwCoreService(gateway).cachedEndpointsOfModule(_commandModule);
    }

    await cacheFrom(_gatewayA, "/mgw-dc-a");
    await cacheFrom(_gatewayB, "/mgw-dc-b");

    expect(await cachedLocations(), ["pairing-A/mgw-dc-a", "pairing-B/mgw-dc-b"]);
  });

  test("a failed gateway batch drops only that gateway's cached endpoint",
      () async {
    await cache(_commandModule, "endpoint-a", "/mgw-dc-a", pairingId: "pairing-A");
    await cache(_commandModule, "endpoint-b", "/mgw-dc-b", pairingId: "pairing-B");
    await cache(_deviceModule, "devices-a", "/dm-a", pairingId: "pairing-A");
    backend.failures["POST /mgw-dc-a/commands/batch"] =
        DioExceptionType.connectionError;
    backend.serveJson("POST", _platformBatch, 200, [
      {"status_code": 200, "message": "ok"}
    ]);

    await DeviceCommandsService.runCommands([gatewayCommand(_gatewayA)]);

    expect(requestsTo("/mgw-dc-a/commands/batch"), hasLength(1));
    expect(await cachedLocations(), ["pairing-A/dm-a", "pairing-B/mgw-dc-b"],
        reason: "the next command to A looks the module up again");
  });

  test("a row cached before endpoints were kept per gateway is not used",
      () async {
    await cache(_commandModule, "endpoint-old", "/legacy");
    backend.serveJson("GET", _gatewayEndpoints, 200, {
      "endpoint-a": {"id": "endpoint-a", "location": "/mgw-dc-a", "ref": "r"}
    });
    backend.serveJson("POST", "/mgw-dc-a/commands/batch", 200, [
      {"status_code": 200, "message": "done"}
    ]);

    final result =
        await DeviceCommandsService.runCommands([gatewayCommand(_gatewayA)]);

    expect(result.single.message, "done");
    expect(requestsTo("/legacy/commands/batch"), isEmpty);
    expect(await cachedLocations(module: _commandModule),
        ["/legacy", "pairing-A/mgw-dc-a"]);
  });

  test("a failed device list drops only that gateway's device-manager "
      "endpoint", () async {
    await cache(_deviceModule, "devices-a", "/dm-a", pairingId: "pairing-A");
    await cache(_deviceModule, "devices-b", "/dm-b", pairingId: "pairing-B");
    await cache(_commandModule, "endpoint-a", "/mgw-dc-a", pairingId: "pairing-A");
    backend.failures["GET /dm-a/devices"] = DioExceptionType.connectionError;
    backend.serveJson("GET", _gatewayEndpoints, 200, {
      "devices-a2": {"id": "devices-a2", "location": "/dm-a2", "ref": "r"}
    });
    backend.serveJson("GET", "/dm-a2/devices", 200, {});

    await DeviceManagerNew(_gatewayA).getDevices();

    expect(requestsTo("/dm-a2/devices").map((r) => r.uri.host), ["gw-a.test"]);
    expect(await cachedLocations(),
        ["pairing-A/dm-a2", "pairing-A/mgw-dc-a", "pairing-B/dm-b"]);
  });
}
