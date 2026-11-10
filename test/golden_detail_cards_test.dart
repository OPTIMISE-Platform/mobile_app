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
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/config/functions/function_config.dart';
import 'package:mobile_app/config/functions/light_functions.dart';
import 'package:mobile_app/live/conversion/casts.dart' show Characteristics;
import 'package:mobile_app/models/aspect.dart';
import 'package:mobile_app/models/characteristic.dart';
import 'package:mobile_app/models/concept.dart';
import 'package:mobile_app/models/content_variable.dart';
import 'package:mobile_app/models/device_class.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/models/function.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/detail_page.dart';

import 'golden_helper.dart';
import 'sensor_switch_fixture.dart';

/// The detail page's Light and Climate cards, built from the function and
/// characteristic ids of the real platform.

const _celsiusId = 'urn:infai:ses:characteristic:5ba31623-0ccb-4488-bfb7-f73b50e03b5a';
const _hsbId = 'urn:infai:ses:characteristic:70dfbf7f-372f-485d-9486-8ce41da8e91c';
const _getBrightness = 'urn:infai:ses:measuring-function:c51a6ea5-90c3-4223-9052-6fe4136386cd';
const _getColourTemperature = 'urn:infai:ses:measuring-function:fb0f474f-c1d7-4a90-971b-a0b9915968f0';
const _getTemperature = 'urn:infai:ses:measuring-function:d19ffeb0-877c-4611-951c-b3fc37d9b9ba';
const _setTemperature = 'urn:infai:ses:controlling-function:df08a869-f6b7-4c8a-ada7-2147255b6d70';

Characteristic _char(String id, String name, String type,
        {double? min, double? max, String unit = '', List<dynamic>? allowed, List<Characteristic>? subs}) =>
    Characteristic(id, name, type, min, max, null, subs, unit, allowed);

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  void register(String name, String getId, String setId, Characteristic base) {
    final s = AppState();
    s.platformFunctions[getId] = PlatformFunction(getId, 'Get-$name', 'concept-$name', 'Get-$name');
    s.platformFunctions[setId] = PlatformFunction(setId, 'Set-$name', 'concept-$name', 'Set-$name');
    s.concepts['concept-$name'] = Concept('concept-$name', name, base.id, [base]);
  }

  DeviceInstance addDevice(String name) {
    final lamp = DeviceClass('class-1', 'Lamps', '');
    AppState().deviceClasses[lamp.id] = lamp;
    AppState().deviceTypes['type-1'] = DeviceType('type-1', name, '', lamp.id, [], null);
    final f = AppState().platformFunctions;
    f[onOffFunction] = PlatformFunction(onOffFunction, 'Get-Binary State', 'concept-on-off', 'Get-Binary State');
    f[setOnFunction] = PlatformFunction(setOnFunction, 'Set-On', '', 'Set Device On');
    f[setOffFunction] = PlatformFunction(setOffFunction, 'Set-Off', '', 'Set Device Off');
    register('Brightness', _getBrightness, setBrightnessFunctionId!,
        _char('char-level', 'Level (0 to 254)', ContentVariable.integer, min: 0, max: 254));
    register('Color Temperature', _getColourTemperature, setColourTemperatureFunctionId!,
        _char(Characteristics.kelvin, 'Kelvin', ContentVariable.float, unit: 'K'));
    register('Color', dotenv.env['FUNCTION_GET_COLOR']!, dotenv.env['FUNCTION_SET_COLOR']!,
        _char(_hsbId, 'HS + Brightness (0-254) (Color)', ContentVariable.structure, subs: [
          _char('h', 'h', ContentVariable.integer, min: 0, max: 360),
          _char('s', 's', ContentVariable.integer, min: 0, max: 100),
          _char('b', 'b', ContentVariable.integer, min: 0, max: 254),
        ]));
    register('Temperature', _getTemperature, _setTemperature,
        _char(_celsiusId, 'Degree Celsius', ContentVariable.float, min: -273.15, unit: '°C'));
    for (final n in ['Device', 'Heating', 'Air', 'Indoor', 'Reading', 'Target', 'Lighting']) {
      AppState().aspects[n.toLowerCase()] = Aspect(n.toLowerCase(), n, null);
    }
    AppState().characteristics['char-off-heat'] =
        _char('char-off-heat', 'Binary State (off/heat)', ContentVariable.string, allowed: ['off', 'heat']);
    reinit();
    final d = DeviceInstance('dev-1', 'dev-1-local', name, null, 'type-1', false, 'owner-1', name, DeviceConnectionStatus.online);
    AppState().devices.add(d);
    return d;
  }

  DeviceState state(DeviceInstance d, String functionId, List<String> aspects, bool controlling, String path,
          {dynamic value, String? characteristicId, String group = 'group-1'}) =>
      DeviceState(value, 'svc-$group', group, functionId, null, controlling, null, null, d.id, path, group, aspectIds: aspects)
        ..deviceInstance = d
        ..characteristicId = characteristicId;

  /// Mounts the page, then sets the readings, which the page clears on opening.
  Future<void> show(WidgetTester tester, DeviceInstance d, {required bool dark}) async {
    final values = {for (final s in d.states) s: s.value};
    await pumpGolden(tester, DetailPage(d, null), dark: dark);
    values.forEach((s, v) {
      s.value = v;
      s.transitioning = false;
    });
    d.notifyStateChanged();
    await tester.pump();
  }

  testWidgets('light card', (tester) async {
    final d = addDevice('Hue lamp');
    const l = ['lighting'];
    d.states
      ..add(state(d, onOffFunction, ['device', 'lighting'], false, 'state', value: true))
      ..add(state(d, setOnFunction, l, true, 'on'))
      ..add(state(d, setOffFunction, l, true, 'off'))
      ..add(state(d, _getBrightness, l, false, 'brightness', value: 150))
      ..add(state(d, setBrightnessFunctionId!, l, true, 'brightness'))
      ..add(state(d, _getColourTemperature, l, false, 'color_temp', value: 3200.0))
      ..add(state(d, setColourTemperatureFunctionId!, l, true, 'color_temp'))
      ..add(state(d, dotenv.env['FUNCTION_GET_COLOR']!, l, false, 'color', value: {'h': 30, 's': 100, 'b': 150}))
      ..add(state(d, dotenv.env['FUNCTION_SET_COLOR']!, l, true, 'color'));
    for (final dark in [false, true]) {
      await show(tester, d, dark: dark);
      await tester.tap(find.text('Color'));
      await tester.pump();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/detail_page_light_card_${dark ? 'dark' : 'light'}.png'));
    }
  });

  testWidgets('climate card', (tester) async {
    final d = addDevice('Radiator thermostat');
    d.states
      ..add(state(d, onOffFunction, ['heating'], false, 'running_state', value: 'heat', group: 'g-run'))
      ..add(state(d, onOffFunction, ['heating', 'device'], false, 'system_mode',
          value: 'heat', characteristicId: 'char-off-heat', group: 'g-mode'))
      ..add(state(d, _getTemperature, ['air', 'indoor', 'reading'], false, 'local_temperature', value: 21.5, group: 'g-t'))
      ..add(state(d, _getTemperature, ['target', 'air', 'indoor'], false, 'setpoint', value: 22.0, group: 'g-t'))
      ..add(state(d, _setTemperature, ['target', 'air', 'indoor'], true, 'setpoint', group: 'g-t'));
    for (final dark in [false, true]) {
      await show(tester, d, dark: dark);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/detail_page_climate_card_${dark ? 'dark' : 'light'}.png'));
    }
  });
}
