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
import 'package:mobile_app/models/aspect.dart';
import 'package:mobile_app/models/characteristic.dart';
import 'package:mobile_app/models/content_variable.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/models/function.dart';
import 'package:mobile_app/widgets/shared/grouped_list_tile.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/detail_labels.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/detail_page.dart';

import 'golden_helper.dart';
import 'sensor_switch_fixture.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(resetAppStateForGolden);

  group('labels and values', () {
    test('a leading Get- or Set- is dropped from the function name', () {
      expect(stripFunctionPrefix('Get-Binary State'), 'Binary State');
      expect(stripFunctionPrefix('Set-Temperature'), 'Temperature');
      expect(stripFunctionPrefix('Set Device On/Off'), 'Set Device On/Off');
      expect(stripFunctionPrefix('Forget-Me'), 'Forget-Me');
    });

    test('a variable path becomes a sentence-case label', () {
      expect(humanizeVariableName('occupied_heating_setpoint'), 'Occupied heating setpoint');
      expect(humanizeVariableName('root.running_state'), 'Running state');
      expect(humanizeVariableName(null), '');
      expect(humanizeVariableName(''), '');
    });

    test('a duration shows its two largest units', () {
      expect(formatDuration(120), '2 min');
      expect(formatDuration(240), '4 min');
      expect(formatDuration(3 * 3600 + 12 * 60), '3 h 12 min');
      expect(formatDuration(5 * 86400 + 3 * 3600 + 59 * 60), '5 d 3 h');
      expect(formatDuration(442122), '5 d 2 h');
    });

    test('only 120 s and more is a duration, only 1000 and more loses its decimals', () {
      expect(formatValueWithUnit(119, 's'), '119 s');
      expect(formatValueWithUnit(120, 's'), '2 min');
      expect(formatValueWithUnit([442122, 442122], 's'), '5 d 2 h');
      expect(formatValueWithUnit(2732.24, 'K'), '2732 K');
      expect(formatValueWithUnit(999.5, 'K'), '999.5 K');
      expect(formatValueWithUnit(-2732.6, 'K'), '-2733 K');
      expect(formatValueWithUnit(5000, ''), '5000');
      expect(formatValueWithUnit(null, 'K'), '- K');
    });

    test('a read-only binary state is text', () {
      expect(readOnlyBinaryText(true), 'On');
      expect(readOnlyBinaryText(false), 'Off');
      expect(readOnlyBinaryText([true, false]), 'Mixed');
      expect(readOnlyBinaryText('heat'), 'Heat');
      expect(readOnlyBinaryText('idle'), 'Idle');
      expect(readOnlyBinaryText(null), '-');
    });
  });

  group('detail page', () {
    const getTemperature = 'urn:infai:ses:measuring-function:temperature';
    const setTemperature = '$controllingFunctionPrefix:set-temperature';
    const getLevel = 'urn:infai:ses:measuring-function:level';
    const setLevel = '$controllingFunctionPrefix:set-level';

    void registerFunctions() {
      registerOnOffFunctions();
      final f = AppState().platformFunctions;
      f[onOffFunction] = PlatformFunction(onOffFunction, 'Get-Binary State', 'concept-on-off', 'Get-Binary State');
      f[setOnFunction] = PlatformFunction(setOnFunction, 'Set-On', '', 'Set Device On');
      f[setOffFunction] = PlatformFunction(setOffFunction, 'Set-Off', '', 'Set Device Off');
      f[getTemperature] = PlatformFunction(getTemperature, 'Get-Temperature', 'concept-temperature', 'Get-Temperature');
      f[setTemperature] = PlatformFunction(setTemperature, 'Set-Temperature', 'concept-temperature', 'Set-Temperature');
      f[getLevel] = PlatformFunction(getLevel, 'Get-Brightness', 'concept-level', 'Get-Brightness');
      f[setLevel] = PlatformFunction(setLevel, 'Set-Brightness', 'concept-level', 'Set-Brightness');
      for (final name in ['Device', 'Button', 'Heating', 'Air', 'Indoor', 'Reading', 'Target', 'Lighting']) {
        AppState().aspects[name.toLowerCase()] = Aspect(name.toLowerCase(), name, null);
      }
    }

    DeviceInstance addDevice() {
      final d = DeviceInstance('dev-1', 'dev-1-local', 'Test device', null, 'type-1', false, 'owner-1', 'Test device',
          DeviceConnectionStatus.online);
      AppState().devices.add(d);
      return d;
    }

    DeviceState state(DeviceInstance d, String functionId, List<String> aspects, bool controlling, String path,
            {String serviceGroup = 'group-1', dynamic value}) =>
        DeviceState(value, 'svc-$serviceGroup', serviceGroup, functionId, null, controlling, null, null, d.id, path, serviceGroup,
            aspectIds: aspects)
          ..deviceInstance = d;

    Future<void> pump(WidgetTester tester, DeviceInstance d) async {
      final values = {for (final s in d.states) s: s.value};
      await pumpGolden(tester, DetailPage(d, null), dark: false);
      // The page clears the readings on opening; set them after its own value
      // load, which fails without a backend.
      values.forEach((s, v) {
        s.value = v;
        s.transitioning = false;
      });
      d.notifyStateChanged();
      await tester.pump();
    }

    // Only list rows: the page header is a ListTile too and may say "Device".
    Finder rowWith(String text) => find.ancestor(
        of: find.descendant(of: find.byType(GroupedListTile), matching: find.text(text)), matching: find.byType(ListTile));

    testWidgets('a smart plug: the switch is a control, the wall button a reading', (tester) async {
      registerFunctions();
      final d = addDevice();
      d.states
        ..add(state(d, onOffFunction, ['device'], false, 'output', serviceGroup: 'out', value: true))
        ..add(state(d, setOnFunction, ['device'], true, 'on', serviceGroup: 'out'))
        ..add(state(d, setOffFunction, ['device'], true, 'off', serviceGroup: 'out'))
        ..add(state(d, onOffFunction, ['button'], false, 'state', serviceGroup: 'in', value: false));
      await pump(tester, d);

      expect(find.text('Control'), findsOneWidget);
      expect(find.text('Readings'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Control')).dy, lessThan(tester.getTopLeft(find.text('Readings')).dy));

      // The switch: its row sits above the readings header and holds a real
      // switch; the button's own title tells the two apart, so it needs no subtitle.
      final switchRow = rowWith('Power').first;
      expect(find.descendant(of: find.byType(GroupedListTile), matching: find.text('Device')), findsNothing);
      expect(tester.getTopLeft(switchRow).dy, lessThan(tester.getTopLeft(find.text('Readings')).dy));
      expect(find.descendant(of: switchRow, matching: find.byType(Switch)), findsOneWidget);

      // The button: below the header, titled by its role, no icon.
      final buttonRow = rowWith('Button input');
      expect(tester.getTopLeft(buttonRow).dy, greaterThan(tester.getTopLeft(find.text('Readings')).dy));
      expect(find.text('Binary State'), findsNothing);
      expect(find.descendant(of: buttonRow, matching: find.text('Off')), findsOneWidget);
      expect(find.descendant(of: buttonRow, matching: find.byType(IconButton)), findsNothing);
      expect(find.descendant(of: buttonRow, matching: find.byType(Switch)), findsNothing);
      expect(find.textContaining('Get-'), findsNothing);
    });

    testWidgets('a thermostat without a card shows the heating states by role', (tester) async {
      registerFunctions();
      final d = addDevice();
      // Not a thermostat card: no setpoint here, only the two heating states.
      d.states
        ..add(state(d, onOffFunction, ['heating'], false, 'running_state', value: 'idle'))
        ..add(state(d, onOffFunction, ['heating', 'device'], false, 'system_mode', value: 'heat')
          ..characteristicId = 'char-off-heat');
      AppState().characteristics['char-off-heat'] =
          Characteristic('char-off-heat', 'Binary State (off/heat)', ContentVariable.string, null, null, null, null, '', ['off', 'heat']);
      await pump(tester, d);

      expect(find.text('Control'), findsNothing);
      // Told apart by their characteristic: idle/heat is running, off/heat enabled.
      expect(find.descendant(of: rowWith('Heating'), matching: find.text('Idle')), findsOneWidget);
      expect(find.descendant(of: rowWith('Heating enabled'), matching: find.text('On')), findsOneWidget);
      expect(find.byIcon(Icons.power_outlined), findsNothing);
      expect(find.descendant(of: find.byType(GroupedListTile), matching: find.byType(IconButton)), findsNothing);
    });

    testWidgets('a lamp: only controls, so no readings section, and plain titles', (tester) async {
      registerFunctions();
      final d = addDevice();
      d.states
        ..add(state(d, onOffFunction, ['device', 'lighting'], false, 'state', value: true))
        ..add(state(d, setOnFunction, ['lighting'], true, 'on'))
        ..add(state(d, setOffFunction, ['lighting'], true, 'off'))
        ..add(state(d, getLevel, ['lighting'], false, 'brightness', value: 128.0))
        ..add(state(d, setLevel, ['lighting'], true, 'brightness'));
      await pump(tester, d);

      expect(find.text('Control'), findsOneWidget);
      expect(find.text('Readings'), findsNothing);
      expect(find.text('Power'), findsOneWidget);
      expect(find.text('Brightness'), findsOneWidget);
      // The switch is a Switch now, not the plug icon.
      expect(find.byType(Switch), findsOneWidget);
      expect(find.byIcon(Icons.power_outlined), findsNothing);
    });
  });
}
