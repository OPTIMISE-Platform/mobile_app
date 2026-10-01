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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/models/sensor_pin.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/widgets/tabs/sensors/sensor_values.dart';
import 'package:mobile_app/widgets/tabs/sensors/switch_commands.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';
import 'sensor_switch_fixture.dart';

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
  testWidgets('read-backs, loads and other writers on the same states',
      (tester) async {
    final backend = PlugBackend();
    backend.serveJson('GET', devicesPath, 200, [
      deviceJson('fan', 'Bathroom fan', deviceTypeId: 'plug'),
      deviceJson('kettle', 'Kitchen kettle', deviceTypeId: 'plug'),
    ]);
    backend.values['fan'] = false;
    backend.values['kettle'] = false;
    backend.values['hall'] = [true, true];
    serveGoldenBackend(backend);
    await warmUpMgwStorage(tester);
    AppState().deviceTypes['plug'] = plugType('plug');
    registerOnOffFunctions();
    final hall = plugGroup('hall', ['class-plug']);
    AppState().deviceGroups.add(hall);
    final pins = [
      plugPin('fan', 'Fan'),
      SensorPin(
        deviceId: 'fan',
        functionId: setOffFunction,
        aspectId: 'power',
        aspectIds: const ['power'],
        serviceGroupKey: 'group-1',
        isControlling: true,
        alias: 'Fan off',
      ),
      plugPin('kettle', 'Kettle'),
      groupPin('hall', 'Hall'),
    ];
    await mountSensorPage(tester, pins);

    // Another path switches the fan off after the tile switched it on; the
    // end of an unrelated command must not bring the tile's read-back back.
    await tester.tap(inCard('Fan', find.byType(Switch)));
    await settle(tester);
    expect(labelOf(tester, 'Fan'), 'On');
    await tester.tap(find.text('Fan off'));
    await settle(tester);
    expect(backend.values['fan'], isFalse);
    expect(labelOf(tester, 'Fan'), 'Off');
    await tester.tap(inCard('Kettle', find.byType(Switch)));
    await settle(tester);
    expect(labelOf(tester, 'Kettle'), 'On');
    expect(labelOf(tester, 'Fan'), 'Off',
        reason: 'the fan was switched off after its tile read "on" back');

    // A load that starts after a read-back reads a newer value than it.
    await tester.tap(inCard('Fan', find.byType(Switch)));
    await settle(tester);
    expect(labelOf(tester, 'Fan'), 'On');
    backend.values['fan'] = false; // switched off at the plug
    AppState().pushRefresh();
    await settle(tester);
    expect(labelOf(tester, 'Fan'), 'Off');

    // A load that read the shared group state before a command finished is
    // corrected also when the page has gone meanwhile.
    final heldLoad = Completer<void>();
    backend.holdLoads = heldLoad;
    AppState().pushRefresh();
    await settle(tester);
    await tester.tap(inCard('Hall', find.byType(Switch)));
    await settle(tester);
    expect(labelOf(tester, 'Hall'), 'Off');
    await tester.pumpWidget(const SizedBox());
    heldLoad.complete();
    backend.holdLoads = null;
    await settle(tester);
    final hallReading =
        hall.states.firstWhere((s) => s.functionId == onOffFunction);
    expect(hallReading.value, [false, false],
        reason: 'the load read "on" before the command switched the hall off');

    // An older load landing after a newer one does not write its values into
    // the shared group state.
    await mountSensorPage(tester, pins);
    expect(labelOf(tester, 'Hall'), 'Off');
    final olderLoad = Completer<void>();
    backend.holdLoads = olderLoad;
    AppState().pushRefresh();
    await settle(tester);
    backend.holdLoads = null;
    backend.values['hall'] = [true, true]; // switched on elsewhere
    AppState().pushRefresh();
    await settle(tester);
    olderLoad.complete();
    await settle(tester);
    expect(labelOf(tester, 'Hall'), 'On');
    expect(hallReading.value, [true, true]);

    // Two pages built before a tap: a tap on each in the same frame sends
    // one command.
    await pumpGolden(
      tester,
      const Scaffold(
        body: Column(
          children: [
            Expanded(child: SensorValues()),
            Expanded(child: SensorValues()),
          ],
        ),
      ),
      dark: false,
      size: const Size(412, 1400),
    );
    await settle(tester);
    final fanSwitches = find.descendant(
        of: find.ancestor(of: find.text('Fan'), matching: find.byType(Card)),
        matching: find.byType(Switch));
    expect(fanSwitches, findsNWidgets(2));
    final controlsBefore = backend.controls.length;
    final held = Completer<void>();
    backend.holdControls = held;
    await tester.tap(fanSwitches.first);
    await tester.tap(fanSwitches.last);
    await tester.pump();
    held.complete();
    backend.holdControls = null;
    await settle(tester);
    expect(backend.controls.length - controlsBefore, 1);

    // A gateway found after the page loaded makes its devices local again.
    await mountSensorPage(tester, pins);
    AppState().clearNetworkData();
    final network = Network('net-1', 'Home', false, ['fan-local'], ['fan'],
        DeviceConnectionStatus.online, '', 'owner-1');
    AppState().networks.add(network);
    await tester.runAsync(() => Settings.setLocalMode(true));
    tester.view.physicalSize = const Size(412, 900);
    await settle(tester);
    expect(labelOf(tester, 'Fan'), 'Not local');
    network.localGateways = [
      MGW('gw', 'gw._snrgy._tcp', 'core-1', '10.0.0.2', networkId: 'net-1'),
    ];
    AppState().notifyListeners();
    await settle(tester);
    expect(labelOf(tester, 'Fan'), isNot('Not local'));
    await tester.runAsync(() => Settings.setLocalMode(false));
  });
}
