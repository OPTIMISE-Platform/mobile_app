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
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/services/device_commands.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';
import 'test_helper.dart';

const _gatewayEndpoints = "/core/api/core-manager/endpoints";
const _gatewayBatch = "/mgw-dc/commands/batch";
const _platformBatch = "/device-command/commands/batch";

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
    await db.writeTxn(() => db.endpoints.put(Endpoint("endpoint-1", "/mgw-dc", "r",
        moduleName: DeviceCommandPath.deviceManagerModuleName)));
  });

  tearDown(() async {
    resetAppStateForGolden();
    resetGoldenBackend();
    await db.writeTxn(() => db.endpoints.clear());
  });

  /// A command for a device served by the gateway at gw.test.
  DeviceCommand gatewayCommand() {
    final d = DeviceInstance("B", "B-local", "B", null, "device-type-1", false,
        "owner-1", "B", DeviceConnectionStatus.online);
    AppState().networks.add(Network("network-B", "Home", false, ["B-local"],
        ["B"], DeviceConnectionStatus.online, "", "owner-1")
      ..localGatewayHosts = ["gw.test"]);
    return DeviceCommand("function-1", "B", "service-1", "aspect-1")
      ..deviceInstance = d;
  }

  Future<int> cachedEndpoints() => db.endpoints
      .where()
      .moduleNameEqualTo(DeviceCommandPath.deviceManagerModuleName)
      .count();

  test("a cached endpoint is used without asking the core-manager", () async {
    backend.serveJson("POST", _gatewayBatch, 200, [
      {"status_code": 200, "message": "done"}
    ]);

    final result = await DeviceCommandsService.runCommands([gatewayCommand()]);

    expect(backend.requests.where((r) => r.uri.path == _gatewayEndpoints),
        isEmpty);
    expect(result.single.message, "done");
    expect(await cachedEndpoints(), 1, reason: "a served batch keeps the cache");
  });

  test("a failed gateway batch drops the cached endpoint", () async {
    backend.failures["POST $_gatewayBatch"] = DioExceptionType.connectionError;
    backend.serveJson("POST", _platformBatch, 200, [
      {"status_code": 200, "message": "ok"}
    ]);

    await DeviceCommandsService.runCommands([gatewayCommand()]);

    expect(backend.requests.where((r) => r.uri.path == _gatewayBatch),
        hasLength(1));
    expect(await cachedEndpoints(), 0,
        reason: "the next command looks the module up again");
  });
}
