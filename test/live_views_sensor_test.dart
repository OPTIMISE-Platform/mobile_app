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

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/models/sensor_pin.dart';
import 'package:mobile_app/models/sensor_tab.dart';
import 'package:mobile_app/services/devices.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/widgets/tabs/sensors/sensor_values.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';
import 'live_views_support.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  final made = <RecordingConnection>[];
  final loadPinnedOriginal = loadPinnedDevices;

  setUp(() {
    made.clear();
    recordConnectionsInto(made);
    // Devices are watched through the cloud: the page's own network load
    // replaces the test's networks with the backend's, which lists none.
    dotenv.env['LIVE_MQTT_URL'] = 'ssl://mqtt.test:28888';
  });

  tearDown(() {
    dotenv.env.remove('LIVE_MQTT_URL');
    loadPinnedDevices = loadPinnedOriginal;
    restoreConnections();
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  // A load reads the stores on the real event loop, each step continuing in
  // the next pump.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  // One testWidgets for the whole sequence: Dio instances are memoized per
  // process, see docs/testing.md.
  testWidgets('the sensor tab watches the device pins of the shown tab only', (tester) async {
    final backend = FakeBackend();
    backend.serveJson('POST', '/device-command/commands/batch', 500, 'boom');
    serveGoldenBackend(backend);
    await warmUpMgwStorage(tester);

    final devices = [testDevice('dev-gw'), testDevice('dev-2')];
    AppState().deviceTypes['type-1'] = DeviceType('type-1', 'Meter', '', 'class', [], null);
    AppState().deviceGroups.add(DeviceGroup('grp-1', 'Group', const [], '', const [], null));
    loadPinnedDevices = (ids) async => DeviceInstanceWithTotal(
          [for (final d in devices) if (ids.contains(d.id)) d],
          devices.length,
        );

    const air = SensorTab(id: 'tab-air', name: 'Air', pins: [
      SensorPin(deviceId: 'dev-gw', functionId: 'fn-1', aspectId: 'a', alias: 'Inside'),
    ]);
    const water = SensorTab(id: 'tab-water', name: 'Water', pins: [
      SensorPin(deviceId: 'dev-2', functionId: 'fn-1', aspectId: 'a', alias: 'Tank'),
      SensorPin(groupId: 'grp-1', deviceClassId: 'c', functionId: 'fn-1', aspectId: 'a', alias: 'Group'),
    ]);
    await tester.runAsync(() => Settings.setSensorTabs([air, water]));

    await pumpGolden(tester, const Scaffold(body: SensorValues()), dark: false);
    await settle(tester);

    // The first tab's device is watched; the group pin of the other tab never
    // opens a connection of its own.
    expect(made, hasLength(1));
    expect(made.single.topics, {cloudTopic(devices[0])});

    // Switching shows the other tab: its device is watched, the first one released.
    await tester.tap(find.text('Water'));
    await settle(tester);
    expect(made.single.topics, {cloudTopic(devices[1])});

    // And back again.
    await tester.tap(find.text('Air'));
    await settle(tester);
    expect(made.single.topics, {cloudTopic(devices[0])});

    // Leaving the page releases the last device.
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    expect(made.single.topics, isEmpty);
  });
}
