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
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/services/api_available.dart';
import 'package:mobile_app/services/device_connection_states.dart';
import 'package:mobile_app/services/mgw_device_manager.dart';
import 'package:mobile_app/shared/dio_factory.dart';
import 'package:mobile_app/shared/error_reporter.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';
import 'sensor_switch_fixture.dart';

const _gatewayEndpoints = "/core/api/core-manager/endpoints";
const _gatewayBatch = "/mgw-dc/commands/batch";
const _gatewayDevices = "/mgw-dc/devices";

/// Holds the platform's connection-state request, the device request that
/// asks for ids, while [statusHold] is set.
class _StatusHoldBackend extends FakeBackend {
  Completer<void>? statusHold;

  List<RequestOptions> get statusRequests => requests
      .where((r) =>
          r.uri.path == devicesPath && r.uri.queryParameters["ids"] != null)
      .toList();

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final hold = statusHold;
    if (hold != null &&
        options.uri.path == devicesPath &&
        options.uri.queryParameters["ids"] != null) {
      requests.add(options);
      await hold.future;
      requests.removeLast();
    }
    return super.fetch(options, requestStream, cancelFuture);
  }
}

DeviceInstance _device(String id,
        {DeviceConnectionStatus state = DeviceConnectionStatus.online}) =>
    DeviceInstance(
        id, "$id-local", id, null, "plug", false, "owner-1", id, state);

/// Registers a network served by the gateway at gw.test, holding [localIds].
void _gatewayNetwork(List<String> localIds) {
  AppState().networks.add(Network("network-gw", "Home", false, localIds,
      const [], DeviceConnectionStatus.online, "", "owner-1")
    ..localGateways = [
      MGW("gw.test", "gw.test", "", "gw.test", networkId: "network-gw")
    ]);
}

/// Serves the gateway's endpoints, its device manager calling every device of
/// [online] online, and its command batch answering [value].
void _serveGateway(FakeBackend backend, List<String> online, Object value) {
  backend.serveJson("GET", _gatewayEndpoints, 200, {
    "endpoint-1": {"id": "endpoint-1", "location": "/mgw-dc", "ref": "r"}
  });
  backend.serveJson("GET", _gatewayDevices, 200, {
    for (final localId in online) localId: {"state": "online"}
  });
  backend.serveJson("POST", _gatewayBatch, 200, [
    {
      "status_code": 200,
      "message": [value]
    }
  ]);
}

DeviceState _onOff(DeviceInstance device) =>
    device.states.singleWhere((s) => s.functionId == onOffFunction);

List<RequestOptions> _platformBatches(FakeBackend backend) =>
    backend.requests.where((r) => r.uri.path == batchPath).toList();

/// Platform requests as they are made, before an outage refuses them.
Future<List<RequestOptions>> _recordPlatformAttempts() async {
  final attempted = <RequestOptions>[];
  final dio = await DioFactory.create(DioConfig.standard);
  final recorder = InterceptorsWrapper(onRequest: (options, handler) {
    attempted.add(options);
    handler.next(options);
  });
  dio.interceptors.insert(0, recorder);
  addTearDown(() => dio.interceptors.remove(recorder));
  return attempted;
}

Future<void> _until(bool Function() done, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail(what);
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  late _StatusHoldBackend backend;
  late List<String> shown;

  setUpAll(() async {
    await setUpGoldenEnvironment();
    // The gateway discovery AppState starts relinks every network to the
    // stored pairings, which would drop the gateways the tests add.
    AppState();
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });

  setUp(() {
    backend = _StatusHoldBackend();
    serveGoldenBackend(backend);
    shown = [];
    ErrorReporter.resetForTest();
    ErrorReporter.present = shown.add;
    AppState().deviceTypes["plug"] = plugType("plug");
    registerOnOffFunctions();
  });

  tearDown(() async {
    await pumpEventQueue();
    ErrorReporter.present = (_) {};
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  test(
      "loadStates hands a gateway value over before the platform answers, "
      "and a later platform failure leaves it", () async {
    _gatewayNetwork(["G-local"]);
    _serveGateway(backend, const [], true);
    final platformHold = Completer<void>();
    backend.holds["POST $batchPath"] = platformHold;
    // Not a list, so the platform path throws out of runCommands.
    backend.serveJson("POST", batchPath, 200, {"not": "a list"});
    final g = _device("G")..prepareStates(plugType("plug"));
    final p = _device("P")..prepareStates(plugType("plug"));
    var gNotified = 0;
    g.stateNotifier.addListener(() => gNotified++);

    final loading = AppState().loadStates([g, p], [], [onOffFunction]);
    await _until(() => _onOff(g).value == true,
        "the gateway value waited for the platform");

    expect(gNotified, 1, reason: "the gateway's device is told at once");
    expect(_onOff(g).transitioning, isFalse);
    expect(_onOff(p).value, isNull);
    expect(_onOff(p).transitioning, isTrue);

    platformHold.complete();
    await loading;

    expect(_onOff(g).value, isTrue,
        reason: "the failure is not written over the gateway's answer");
    expect(_onOff(p).value, isNull);
    expect(_onOff(p).transitioning, isFalse);
    expect(shown, ["failed to loadStates"]);
  });

  group("the device list", () {
    Future<void> serveList() async {
      backend.serveJson("GET", "/device-repository/device-groups", 200, []);
      backend.serveJson("GET", "/device-repository/extended-hubs", 200, []);
      backend.serveJson("GET", "/device-repository/device-types", 200, []);
      backend.serveJson(
          "GET", "/device-repository/user-device-types", 200, []);
      backend.serveDevicesPaged([
        deviceJson("G", "G", deviceTypeId: "plug"),
        deviceJson("P", "P", deviceTypeId: "plug"),
      ]);
      // Before the type: the start replaces the device types.
      await AppState().ensureInitialized();
      shown.clear();
      AppState().deviceTypes["plug"] = plugType("plug");
      _gatewayNetwork(["G-local"]);
      _serveGateway(backend, ["G-local"], true);
    }

    DeviceInstance listed(String id) =>
        AppState().devices.singleWhere((d) => d.id == id);

    test("loads a gateway's values without waiting for the platform's states",
        () async {
      await serveList();
      backend.serveJson("POST", batchPath, 200, [
        {
          "status_code": 200,
          "message": [false]
        }
      ]);
      backend.statusHold = Completer<void>();

      await AppState().searchDevices(DeviceSearchFilter.empty(), true);
      await _until(() => _onOff(listed("G")).value == true,
          "the gateway's device waited for the platform's states");

      expect(backend.statusRequests, hasLength(1));
      expect(_platformBatches(backend), isEmpty,
          reason: "a device no gateway serves waits for its state");

      backend.statusHold!.complete();
      await _until(() => _onOff(listed("P")).value == false,
          "the platform's device never got its value");
      expect(shown, isEmpty);
    });

    test("does not ask the unreachable platform for states", () async {
      await serveList();
      final attempted = await _recordPlatformAttempts();
      // The page leaves before the outage is noticed.
      backend.holdDevices = Completer<void>();
      final searching =
          AppState().searchDevices(DeviceSearchFilter.empty(), true);
      await _until(() => backend.requests.any((r) => r.uri.path == devicesPath),
          "no page request");
      ApiAvailableService.setUnreachableForTest(true);
      backend.holdDevices!.complete();
      await searching;

      await _until(() => _onOff(listed("G")).value == true,
          "the gateway's device got no value");
      await _until(() => !_onOff(listed("P")).transitioning,
          "the platform's device was never answered");
      expect(
          attempted.where((r) =>
              r.uri.path == devicesPath &&
              r.uri.queryParameters["ids"] != null),
          isEmpty);
      expect(_platformBatches(backend), isEmpty);
      expect(_onOff(listed("P")).value, isNull);
      expect(shown, isEmpty);
    });
  });

  group("while the platform is unreachable", () {
    test("a device no gateway serves becomes unknown without a request",
        () async {
      final attempted = await _recordPlatformAttempts();
      ApiAvailableService.setUnreachableForTest(true);
      final p = _device("P", state: DeviceConnectionStatus.offline);

      await refreshDeviceConnectionStates([p]);

      expect(p.connection_state, DeviceConnectionStatus.unknown);
      expect(attempted, isEmpty);
    });

    test("a gateway that fails is not followed by a platform request",
        () async {
      _gatewayNetwork(["G-local"]);
      backend.failures["GET $_gatewayEndpoints"] =
          DioExceptionType.connectionError;
      final attempted = await _recordPlatformAttempts();
      ApiAvailableService.setUnreachableForTest(true);
      final g = _device("G");

      await MgwDeviceManager.updateDeviceConnectionStatusFromMgw([g]);

      expect(backend.requests, isNotEmpty, reason: "the gateway was asked");
      expect(attempted, isEmpty);
      expect(shown, isEmpty);
    });
  });
}
