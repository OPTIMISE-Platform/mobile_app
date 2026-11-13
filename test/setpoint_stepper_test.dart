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
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/config/functions/function_config.dart';
import 'package:mobile_app/models/characteristic.dart';
import 'package:mobile_app/models/concept.dart';
import 'package:mobile_app/models/content_variable.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/control_cards.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/inline_control.dart';
import 'package:mobile_app/widgets/tabs/shared/device_state_action.dart';

import 'golden_helper.dart';
import 'thermostat_fixture.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  setUp(registerThermostatMetadata);

  tearDown(resetAppStateForGolden);

  final device = DeviceInstance(
      'trv', 'trv-local', 'Radiator', null, 'dt-trvzb', false, 'owner-1', 'Radiator', DeviceConnectionStatus.online);

  DeviceState state(String functionId, bool controlling, String path, List<String> aspects, [dynamic value]) =>
      DeviceState(value, 'svc-$path', 'group-t', functionId, null, controlling, null, null, device.id, path, 'Thermostat',
          aspectIds: aspects)
        ..deviceInstance = device;

  group('the setpoint stepper\'s range', () {
    test('a thermostat\'s setpoint without a maximum takes 5 to 30 °C, anything else only its characteristic\'s bounds', () {
      final control = state(setTemperature, true, 'set', setpointAspects);

      final thermostat = climateSetpointSpec(control, thermostat: true)!;
      expect([thermostat.min, thermostat.max], [5.0, 30.0]);
      final other = climateSetpointSpec(control)!;
      expect([other.min, other.max], [-273.15, null], reason: 'a boiler sets its water far above 30 °C');

      AppState().concepts['concept-temperature'] = Concept('concept-temperature', 'Temperature', celsius, [
        Characteristic(celsius, 'Degree Celsius', ContentVariable.float, 4, 35, null, null, '°C', null),
      ]);
      reinit();
      final bounded = climateSetpointSpec(control, thermostat: true)!;
      expect([bounded.min, bounded.max], [4.0, 35.0], reason: 'bounds of its own win');
    });
  });

  group('a value outside the bounds', () {
    Future<List<dynamic>> pumpStepper(WidgetTester tester, dynamic value) async {
      final sent = <dynamic>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: InlineControl(
            spec: const InlineControlSpec(InlineControlKind.stepper, min: 5, max: 30),
            value: value,
            unit: '°C',
            busy: false,
            enabled: true,
            compact: true,
            onSend: (v) async => sent.add(v),
          ),
        ),
      ));
      return sent;
    }

    IconButton button(WidgetTester tester, IconData icon) => tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon));

    testWidgets('moves one step towards them, never onto the bound', (tester) async {
      final sent = await pumpStepper(tester, 55.0);
      expect(button(tester, Icons.add).onPressed, isNull, reason: 'further away from the bounds');
      await tester.tap(find.byTooltip('Decrease'));
      await tester.pump(inlineControlDebounce);
      await tester.pump();
      expect(sent, [54.5]);

      final low = await pumpStepper(tester, 3.0);
      expect(button(tester, Icons.remove).onPressed, isNull);
      await tester.tap(find.byTooltip('Increase'));
      await tester.pump(inlineControlDebounce);
      await tester.pump();
      expect(low, [3.5]);
    });

    testWidgets('a value inside them stops at the bound', (tester) async {
      final sent = await pumpStepper(tester, 29.5);
      await tester.tap(find.byTooltip('Increase'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(button(tester, Icons.add).onPressed, isNull);
      await tester.pump(inlineControlDebounce);
      await tester.pump();
      expect(sent, [30.0]);
    });
  });

  group('the external temperature input', () {
    test('starts from the measured value on its aspects, not from the setpoint', () {
      final measured = state(getTemperature, false, 'local', readingAspects, 19.5);
      final setpoint = state(getTemperature, false, 'setpoint', setpointAspects, 21.0);
      final input = state(setTemperature, true, 'external', readingAspects);
      final states = [measured, setpoint, state(setTemperature, true, 'set', setpointAspects), input];

      expect(readingsOfControl(input, states, isGroup: false), [same(measured)]);
      expect(controlStartValue(input, states, isGroup: false), 19.5);
      final start = inlineStartValue(input, states, isGroup: false)!;
      expect(inlineControlSpec(input, start.value, reading: measured)?.kind, InlineControlKind.stepper);
      expect(measured.controlsFor(states, setTemperature), isEmpty, reason: 'the measured value is still no setting');
    });
  });
}
