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

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/services/device_connection_states.dart';
import 'package:mobile_app/services/devices.dart';
import 'package:mobile_app/widgets/tabs/sensors/sensor_values.dart';
import 'package:mobile_app/widgets/tabs/sensors/switch_commands.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';
import 'sensor_switch_fixture.dart';

/// Answers the device list with the next of [states] per request, the last
/// one repeating.
class _ConnectionBackend extends PlugBackend {
  List<String> states = const ['online'];
  final List<RequestOptions> deviceRequests = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) {
    if (options.uri.path == devicesPath) {
      final ids = options.uri.queryParameters['ids']!.split(',');
      final state =
          states[deviceRequests.length.clamp(0, states.length - 1)];
      serveJson('GET', devicesPath, 200, [
        for (final id in ids)
          deviceJson(id, 'Device $id',
              deviceTypeId: 'plug', connectionState: state),
      ]);
      deviceRequests.add(options);
    }
    return super.fetch(options, requestStream, cancelFuture);
  }
}

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() async {
    resetAppStateForGolden();
    resetGoldenBackend();
    SwitchCommands.resetForTest();
  });

  // One testWidgets for every case, see sensor_switch_tile_device_test.dart.
  testWidgets('the page refreshes the connection state before the values',
      (tester) async {
    final backend = _ConnectionBackend();
    backend.values['fan'] = true;
    serveGoldenBackend(backend);
    await warmUpMgwStorage(tester);
    AppState().deviceTypes['plug'] = plugType('plug');
    registerOnOffFunctions();

    // Fetched from the platform: its connection state is current already.
    await mountSensorPage(tester, [plugPin('fan', 'Fan')]);
    expect(backend.deviceRequests, hasLength(1),
        reason: 'no second request for what the first one answered');
    expect(labelOf(tester, 'Fan'), 'On');

    // Served from the cache, which still calls the fan online.
    final original = loadPinnedDevices;
    loadPinnedDevices = (ids) async {
      final fetched = await original(ids);
      return DeviceInstanceWithTotal(fetched.devices, fetched.total,
          fromCache: true);
    };
    addTearDown(() => loadPinnedDevices = original);
    backend.deviceRequests.clear();
    backend.commands.clear();
    backend.states = ['online', 'offline'];
    await mountSensorPage(tester, [plugPin('fan', 'Fan')]);

    expect(backend.deviceRequests, hasLength(2),
        reason: 'the pinned devices, then their status from the platform');
    expect(labelOf(tester, 'Fan'), 'Offline');
    expect(switchOf(tester, 'Fan').onChanged, isNull);
    expect(backend.commandsFor('fan'), isEmpty,
        reason: 'no values are requested from a device known to be offline');

    // The helper itself: a changed state is announced, a failed request
    // leaves the state unknown rather than the stale one, and the ids go out
    // in chunks of 50.
    await tester.runAsync(() async {
      final device = DeviceInstance('fan', 'fan-local', 'Bathroom fan', null,
          'plug', false, 'owner-1', 'Bathroom fan',
          DeviceConnectionStatus.online);
      // What a listening tile saw at each rebuild.
      final seen = <DeviceConnectionStatus>[];
      device.stateNotifier
          .addListener(() => seen.add(device.connection_state));

      await refreshDeviceConnectionStates([device]);
      expect(device.connection_state, DeviceConnectionStatus.offline);
      expect(seen.last, DeviceConnectionStatus.offline,
          reason: 'the change is announced after it is made');

      backend.failures['GET $devicesPath'] = DioExceptionType.connectionError;
      device.connection_state = DeviceConnectionStatus.online;
      seen.clear();
      await refreshDeviceConnectionStates([device]);
      expect(device.connection_state, DeviceConnectionStatus.unknown);
      expect(seen.last, DeviceConnectionStatus.unknown);
      backend.failures.clear();

      backend.deviceRequests.clear();
      backend.states = ['offline'];
      final many = [
        for (var i = 0; i < 60; i++)
          DeviceInstance('d$i', 'd$i-local', 'Device $i', null, 'plug', false,
              'owner-1', 'Device $i', DeviceConnectionStatus.online),
      ];
      await refreshDeviceConnectionStates(many);
      expect(
          backend.deviceRequests
              .map((r) => r.uri.queryParameters['ids']!.split(',').length),
          unorderedEquals([50, 10]));
      expect(many.map((d) => d.connection_state),
          everyElement(DeviceConnectionStatus.offline));

      backend.deviceRequests.clear();
      await refreshDeviceConnectionStates(many, platformStatesFresh: true);
      expect(backend.deviceRequests, isEmpty);
    });
    // Outlasts the toast plugin's own 2s timer.
    await tester.pump(const Duration(seconds: 3));
  });
}
