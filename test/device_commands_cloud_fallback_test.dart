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
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_command.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/services/device_commands.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/error_reporter.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

const _platformBatch = "/device-command/commands/batch";
const _gatewayEndpoints = "/core/api/core-manager/endpoints";
const _gatewayBatch = "/mgw-dc/commands/batch";

void main() {
  late FakeBackend backend;

  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  setUp(() {
    backend = FakeBackend();
    serveGoldenBackend(backend);
  });

  tearDown(() {
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  /// A command without a device instance, which the platform answers.
  DeviceCommand platformCommand(String deviceId) =>
      DeviceCommand("function-1", deviceId, "service-1", "aspect-1");

  /// A command for a device in a network served by the gateway at [hosts].
  /// Registers that network, or joins the one of [sharesNetworkOf], so call it
  /// before the first runCommands.
  DeviceCommand gatewayCommand(String deviceId,
      {List<String>? hosts = const ["gw.test"],
      String functionId = "function-1",
      String? sharesNetworkOf}) {
    final d = DeviceInstance(deviceId, "$deviceId-local", deviceId, null,
        "device-type-1", false, "owner-1", deviceId,
        DeviceConnectionStatus.online);
    if (sharesNetworkOf != null) {
      AppState()
          .networks
          .singleWhere((n) => n.id == "network-$sharesNetworkOf")
          .device_local_ids!
          .add("$deviceId-local");
    } else {
      final network = Network("network-$deviceId", "Home", false,
          ["$deviceId-local"], [deviceId], DeviceConnectionStatus.online, "",
          "owner-1")
        ..localGatewayHosts = hosts;
      AppState().networks.add(network);
    }
    return DeviceCommand(functionId, deviceId, "service-1", "aspect-1")
      ..deviceInstance = d;
  }

  void serveGatewayEndpoints() {
    backend.serveJson("GET", _gatewayEndpoints, 200, {
      "endpoint-1": {"id": "endpoint-1", "location": "/mgw-dc", "ref": "r"}
    });
  }

  List<RequestOptions> requestsTo(String method, String path) => backend
      .requests
      .where((r) => r.method.toUpperCase() == method && r.uri.path == path)
      .toList();

  /// Device ids in one batch request. The platform request carries a JSON
  /// string, the gateway request the command list itself.
  List<String?> sentDeviceIds(RequestOptions r) {
    final data = r.data;
    final list = data is String ? jsonDecode(data) as List : data as List;
    return [
      for (final c in list)
        c is DeviceCommand ? c.device_id : c["device_id"] as String?
    ];
  }

  List<String?> allSentDeviceIds() => [
        for (final r in [
          ...requestsTo("POST", _platformBatch),
          ...requestsTo("POST", _gatewayBatch)
        ])
          ...sentDeviceIds(r)
      ];

  test("platform failure is answered once", () async {
    backend.serveJson("POST", _platformBatch, 500, null);

    final result =
        await DeviceCommandsService.runCommands([platformCommand("A")]);

    expect(requestsTo("POST", _platformBatch), hasLength(1),
        reason: "a failed platform batch is not sent again");
    expect(result, hasLength(1));
    expect(result.single.status_code, 502);
    expect(result.single.message, "platform answered 500");
  });

  test("a platform 513 is final", () async {
    backend.serveJson("POST", _platformBatch, 200, [
      {"status_code": 513, "message": "x"}
    ]);

    final result =
        await DeviceCommandsService.runCommands([platformCommand("A")]);

    expect(requestsTo("POST", _platformBatch), hasLength(1));
    expect(result.single.status_code, 513);
    expect(result.single.message, "x");
  });

  test("a gateway that fails hands its commands to the platform once",
      () async {
    backend.serveJson("POST", _platformBatch, 200, [
      {"status_code": 200, "message": "ok"}
    ]);
    final command = gatewayCommand("B");

    final result = await DeviceCommandsService.runCommands([command]);

    expect(requestsTo("GET", _gatewayEndpoints), hasLength(1),
        reason: "the gateway was asked first");
    expect(requestsTo("POST", _gatewayBatch), isEmpty);
    final platform = requestsTo("POST", _platformBatch);
    expect(platform, hasLength(1));
    expect(sentDeviceIds(platform.single), ["B"]);
    expect(result.single.status_code, 200);
  });

  test("a gateway 513 goes to the platform once", () async {
    serveGatewayEndpoints();
    backend.serveJson("POST", _gatewayBatch, 200, [
      {"status_code": 513, "message": "not here"}
    ]);
    backend.serveJson("POST", _platformBatch, 200, [
      {"status_code": 200, "message": "ok"}
    ]);
    final command = gatewayCommand("B");

    final result = await DeviceCommandsService.runCommands([command]);

    expect(requestsTo("POST", _gatewayBatch), hasLength(1));
    final platform = requestsTo("POST", _platformBatch);
    expect(platform, hasLength(1));
    expect(sentDeviceIds(platform.single), ["B"]);
    expect(result.single.status_code, 200);
    expect(result.single.message, "ok");
  });

  test("a gateway 200 never reaches the platform", () async {
    serveGatewayEndpoints();
    backend.serveJson("POST", _gatewayBatch, 200, [
      {"status_code": 200, "message": "done"}
    ]);
    final command = gatewayCommand("B");

    final result = await DeviceCommandsService.runCommands([command]);

    expect(requestsTo("POST", _gatewayBatch), hasLength(1));
    expect(requestsTo("POST", _platformBatch), isEmpty);
    expect(result.single.status_code, 200);
    expect(result.single.message, "done");
  });

  test("a mixed batch keeps every command to one send and its own index",
      () async {
    serveGatewayEndpoints();
    backend.serveJson("POST", _gatewayBatch, 200, [
      {"status_code": 513, "message": "not here"}
    ]);
    // A's platform answer is a 513 too, which must stay A's final answer
    // rather than join B's retry.
    backend.serveJson("POST", _platformBatch, 200, [
      {"status_code": 513, "message": "A"}
    ]);
    // The gateway answers only once A's platform batch has been answered, so
    // the platform route can switch to B's body in between.
    final gatewayHold = Completer<void>();
    backend.holds["POST $_gatewayBatch"] = gatewayHold;
    final commands = [platformCommand("A"), gatewayCommand("B")];

    final running = DeviceCommandsService.runCommands(commands);
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (requestsTo("POST", _platformBatch).isEmpty ||
        requestsTo("POST", _gatewayBatch).isEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        fail("the first round never reached both platform and gateway");
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    backend.serveJson("POST", _platformBatch, 200, [
      {"status_code": 200, "message": "B"}
    ]);
    gatewayHold.complete();
    final result = await running;

    final platform = requestsTo("POST", _platformBatch);
    expect(platform, hasLength(2));
    expect(sentDeviceIds(platform[0]), ["A"]);
    expect(sentDeviceIds(platform[1]), ["B"]);
    expect(requestsTo("POST", _gatewayBatch), hasLength(1));
    expect(allSentDeviceIds()..sort(), ["A", "B", "B"],
        reason: "A once to the platform, B once to the gateway and once to "
            "the platform");
    expect(result, hasLength(2));
    expect(result[0].status_code, 513);
    expect(result[0].message, "A");
    expect(result[1].status_code, 200);
    expect(result[1].message, "B");
  });

  // Production leaves the host list null when no gateway is reachable; the
  // field's contract allows an empty list as well.
  for (final (label, hosts) in [("no host list", null), ("an empty host list", <String>[])]) {
    test("a network with $label is answered by the platform", () async {
      backend.serveJson("POST", _platformBatch, 200, [
        {"status_code": 200, "message": "ok"}
      ]);
      final command = gatewayCommand("B", hosts: hosts);

      final result = await DeviceCommandsService.runCommands([command]);

      expect(requestsTo("GET", _gatewayEndpoints), isEmpty);
      expect(requestsTo("POST", _platformBatch), hasLength(1));
      expect(result.single.status_code, 200);
    });
  }

  test("a command listed twice gets an answer at each of its indices",
      () async {
    backend.serveJson("POST", _platformBatch, 200, [
      {"status_code": 200, "message": "first"},
      {"status_code": 200, "message": "second"}
    ]);
    final command = platformCommand("A");

    final result = await DeviceCommandsService.runCommands([command, command]);

    expect(requestsTo("POST", _platformBatch), hasLength(1));
    expect(result.map((r) => r.message), ["first", "second"]);
  });

  test("a platform reply shorter than the batch reports the rest as 502",
      () async {
    backend.serveJson("POST", _platformBatch, 200, [
      {"status_code": 200, "message": "ok"}
    ]);

    final result = await DeviceCommandsService.runCommands(
        [platformCommand("A"), platformCommand("B")]);

    expect(requestsTo("POST", _platformBatch), hasLength(1));
    expect(result.map((r) => r.status_code), [200, 502]);
  });

  test("a command is sent without its device object", () async {
    backend.serveJson("POST", _platformBatch, 200, [
      {"status_code": 200, "message": "ok"}
    ]);
    // Its local id belongs to no registered network, so it goes to the
    // platform.
    final command = platformCommand("A")
      ..deviceInstance = DeviceInstance("A", "A-local", "A", null,
          "device-type-1", false, "owner-1", "A",
          DeviceConnectionStatus.online);

    final result = await DeviceCommandsService.runCommands([command]);

    final platform = requestsTo("POST", _platformBatch);
    expect(platform, hasLength(1));
    final sent = (jsonDecode(platform.single.data as String) as List).single
        as Map<String, dynamic>;
    expect(sent["device_id"], "A");
    expect(sent.containsKey("deviceInstance"), isFalse);
    expect(sent.containsKey("deviceGroup"), isFalse);
    expect(result.single.status_code, 200);
  });

  test(
      "a gateway that takes the batch and does not answer keeps its controls "
      "and hands its reads to the platform", () async {
    serveGatewayEndpoints();
    backend.failures["POST $_gatewayBatch"] = DioExceptionType.receiveTimeout;
    backend.serveJson("POST", _platformBatch, 200, [
      {"status_code": 200, "message": "ok"}
    ]);
    final control = gatewayCommand("B",
        functionId: "urn:infai:ses:controlling-function:set-on");
    final read = gatewayCommand("C",
        functionId: "urn:infai:ses:measuring-function:on-off",
        sharesNetworkOf: "B");

    final result = await DeviceCommandsService.runCommands([control, read]);

    expect(requestsTo("POST", _gatewayBatch), hasLength(1));
    final platform = requestsTo("POST", _platformBatch);
    expect(platform, hasLength(1));
    expect(sentDeviceIds(platform.single), ["C"],
        reason: "the gateway may still run the control, a read is idempotent");
    expect(result[0].status_code, 502);
    expect(result[0].message, "gateway took the command but did not answer");
    expect(result[1].status_code, 200);
    expect(result[1].message, "ok");
  });

  test("a gateway that refuses the connection hands its commands to the platform",
      () async {
    serveGatewayEndpoints();
    backend.failures["POST $_gatewayBatch"] = DioExceptionType.connectionError;
    backend.serveJson("POST", _platformBatch, 200, [
      {"status_code": 200, "message": "ok"}
    ]);
    final command = gatewayCommand("B");

    final result = await DeviceCommandsService.runCommands([command]);

    expect(requestsTo("POST", _gatewayBatch), hasLength(1));
    final platform = requestsTo("POST", _platformBatch);
    expect(platform, hasLength(1));
    expect(sentDeviceIds(platform.single), ["B"]);
    expect(result.single.status_code, 200);
  });

  test(
      "a gateway whose endpoint lookup times out hands its commands to the "
      "platform", () async {
    backend.failures["GET $_gatewayEndpoints"] =
        DioExceptionType.receiveTimeout;
    backend.serveJson("POST", _platformBatch, 200, [
      {"status_code": 200, "message": "ok"}
    ]);
    final command = gatewayCommand("B");

    final result = await DeviceCommandsService.runCommands([command]);

    expect(requestsTo("GET", _gatewayEndpoints), hasLength(1));
    expect(requestsTo("POST", _gatewayBatch), isEmpty);
    final platform = requestsTo("POST", _platformBatch);
    expect(platform, hasLength(1));
    expect(sentDeviceIds(platform.single), ["B"]);
    expect(result.single.status_code, 200);
  });

  test("both batch requests wait longer than device-command's own timeout",
      () async {
    serveGatewayEndpoints();
    backend.serveJson("POST", _gatewayBatch, 200, [
      {"status_code": 200, "message": "g"}
    ]);
    backend.serveJson("POST", _platformBatch, 200, [
      {"status_code": 200, "message": "p"}
    ]);
    final commands = [platformCommand("A"), gatewayCommand("B")];

    await DeviceCommandsService.runCommands(commands);

    final batches = [
      ...requestsTo("POST", _platformBatch),
      ...requestsTo("POST", _gatewayBatch)
    ];
    expect(batches, hasLength(2));
    for (final r in batches) {
      expect(r.uri.queryParameters["timeout"], "10s");
      expect(r.receiveTimeout, greaterThan(const Duration(seconds: 10)),
          reason: "the client must outlast the endpoint's own timeout");
    }
  });

  test("a platform that cannot be reached is answered with the offline message",
      () async {
    backend.failures["POST $_platformBatch"] = DioExceptionType.connectionError;

    final result =
        await DeviceCommandsService.runCommands([platformCommand("A")]);

    expect(requestsTo("POST", _platformBatch), hasLength(1));
    expect(result.single.status_code, 502);
    expect(result.single.message, ErrorReporter.offlineMessage);
  });

  test("in local mode the platform batch is refused with the offline message",
      () async {
    await Settings.setLocalMode(true);
    addTearDown(() => Settings.setLocalMode(false));
    backend.serveJson("POST", _platformBatch, 200, [
      {"status_code": 200, "message": "ok"}
    ]);

    final result =
        await DeviceCommandsService.runCommands([platformCommand("A")]);

    expect(requestsTo("POST", _platformBatch), isEmpty,
        reason: "the availability interceptor rejects before the adapter");
    expect(result.single.status_code, 502);
    expect(result.single.message, ErrorReporter.offlineMessage);
  });
}
