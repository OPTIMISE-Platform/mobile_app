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
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/services/api_available.dart';
import 'package:mobile_app/services/devices.dart';
import 'package:mobile_app/shared/dio_factory.dart';
import 'package:mobile_app/widgets/tabs/sensors/sensor_values.dart';
import 'package:mobile_app/widgets/tabs/sensors/switch_commands.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';
import 'sensor_switch_fixture.dart';

/// Holds the platform's connection-state request while [statusHold] is set.
class _Backend extends PlugBackend {
  Completer<void>? statusHold;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final hold = statusHold;
    if (hold != null && options.uri.path == devicesPath) await hold.future;
    return super.fetch(options, requestStream, cancelFuture);
  }
}

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
    // The gateway discovery AppState starts relinks every network to the
    // stored pairings, which would drop the gateway the test adds.
    AppState();
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });

  tearDown(() async {
    resetAppStateForGolden();
    resetGoldenBackend();
    SwitchCommands.resetForTest();
  });

  // One testWidgets for every case, see sensor_switch_tile_device_test.dart.
  testWidgets('a gateway value does not wait for the platform', (tester) async {
    final toasts = captureToasts();
    final backend = _Backend();
    backend.values['P'] = false;
    backend.serveJson('GET', devicesPath, 200, [
      deviceJson('P', 'P', deviceTypeId: 'plug'),
    ]);
    backend.serveJson('GET', '/core/api/core-manager/endpoints', 200, {
      'endpoint-1': {'id': 'endpoint-1', 'location': '/mgw-dc', 'ref': 'r'}
    });
    backend.serveJson('GET', '/mgw-dc/devices', 200, {
      'G-local': {'state': 'online'}
    });
    backend.serveJson('POST', '/mgw-dc/commands/batch', 200, [
      {
        'status_code': 200,
        'message': [true]
      }
    ]);
    serveGoldenBackend(backend);
    await warmUpMgwStorage(tester);
    AppState().deviceTypes['plug'] = plugType('plug');
    registerOnOffFunctions();
    AppState().networks.add(Network('network-gw', 'Home', false,
        const ['G-local'], const [], DeviceConnectionStatus.online, '',
        'owner-1')
      ..localGateways = [
        MGW('gw.test', 'gw.test', '', 'gw.test', networkId: 'network-gw')
      ]);
    // Served from the cache, so the platform is asked for P's state; the
    // cache still calls P offline.
    final original = loadPinnedDevices;
    loadPinnedDevices = (ids) async => DeviceInstanceWithTotal([
          DeviceInstance('G', 'G-local', 'G', null, 'plug', false, 'owner-1',
              'G', DeviceConnectionStatus.online),
          DeviceInstance('P', 'P-local', 'P', null, 'plug', false, 'owner-1',
              'P', DeviceConnectionStatus.offline),
        ], 2, fromCache: true);
    addTearDown(() => loadPinnedDevices = original);
    final pins = [plugPin('G', 'Gate'), plugPin('P', 'Plat')];

    backend.statusHold = Completer<void>();
    await mountSensorPage(tester, pins);

    expect(labelOf(tester, 'Gate'), 'On',
        reason: 'shown while the platform has not answered for P');
    expect(backend.commandsFor('P'), isEmpty,
        reason: 'P waits for its state');

    backend.statusHold!.complete();
    backend.statusHold = null;
    await settle(tester);
    expect(labelOf(tester, 'Plat'), 'Off');

    // While the platform is unreachable it is not asked for P's state, which
    // the cache cannot vouch for.
    final attempted = <RequestOptions>[];
    final dio =
        (await tester.runAsync(() => DioFactory.create(DioConfig.standard)))!;
    final recorder = InterceptorsWrapper(onRequest: (options, handler) {
      attempted.add(options);
      handler.next(options);
    });
    dio.interceptors.insert(0, recorder);
    addTearDown(() => dio.interceptors.remove(recorder));
    ApiAvailableService.setUnreachableForTest(true);
    backend.commands.clear();
    await mountSensorPage(tester, pins);

    expect(labelOf(tester, 'Gate'), 'On');
    expect(labelOf(tester, 'Plat'), 'Unknown',
        reason: 'not the offline the cache holds');
    expect(attempted.where((r) => r.uri.path == devicesPath), isEmpty);
    expect(backend.commandsFor('P'), isEmpty);
    expect(toasts, isEmpty);
    // Outlasts the toast plugin's own 2s timer.
    await tester.pump(const Duration(seconds: 3));
  });
}
