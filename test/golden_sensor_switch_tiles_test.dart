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

@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/sensor_pin.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';
import 'sensor_switch_fixture.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  Future<void> serve(WidgetTester tester) async {
    final backend = PlugBackend();
    backend.serveJson('GET', devicesPath, 200, [
      deviceJson('fan', 'Bathroom fan', deviceTypeId: 'plug'),
      deviceJson('lamp', 'Desk lamp', deviceTypeId: 'plug'),
      deviceJson('pump', 'Garden pump', deviceTypeId: 'plug'),
      deviceJson('heater', 'Heater',
          deviceTypeId: 'plug', connectionState: 'offline'),
    ]);
    backend.values['fan'] = true;
    backend.values['lamp'] = false;
    // No value for the pump: its read answers 502.
    serveGoldenBackend(backend);
    await warmUpMgwStorage(tester);
    AppState().deviceTypes['plug'] = plugType('plug');
    registerOnOffFunctions();
  }

  // After setUpAll, which loads the function ids.
  List<SensorPin> pins() => [
    plugPin('fan', 'Fan'),
    plugPin('lamp', 'Reading light in the north-west corner of the study'),
    plugPin('pump', 'Pump'),
    plugPin('heater', 'Heating'),
  ];

  // All captures in one test - see golden_device_tabs_shell_test.dart for why.
  testWidgets('sensor switch tiles', (tester) async {
    for (final dark in [false, true]) {
      final suffix = dark ? 'dark' : 'light';
      await serve(tester);
      await mountSensorPage(tester, pins(), dark: dark);
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile('goldens/sensor_switch_tiles_$suffix.png'));
      resetAppStateForGolden();
      resetGoldenBackend();
    }

    await serve(tester);
    await mountSensorPage(tester, pins(), textScale: 2.0);
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile('goldens/sensor_switch_tiles_scale_2.png'));
  });
}
