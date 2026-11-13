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

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
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
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/models/function.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/colour_value.dart';
import 'package:mobile_app/shared/device_controls.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/control_cards.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/detail_labels.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/detail_page.dart';
import 'package:mobile_app/widgets/shared/grouped_list_tile.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';
import 'sensor_switch_fixture.dart';

const _celsiusId = 'urn:infai:ses:characteristic:5ba31623-0ccb-4488-bfb7-f73b50e03b5a';
const _getBrightness = 'urn:infai:ses:measuring-function:c51a6ea5-90c3-4223-9052-6fe4136386cd';
const _getTemperatureColour = 'urn:infai:ses:measuring-function:fb0f474f-c1d7-4a90-971b-a0b9915968f0';
const _getTemperature = 'urn:infai:ses:measuring-function:d19ffeb0-877c-4611-951c-b3fc37d9b9ba';
const _setTemperature = 'urn:infai:ses:controlling-function:df08a869-f6b7-4c8a-ada7-2147255b6d70';
const _getEnergy = 'urn:infai:ses:measuring-function:energy';

Characteristic _char(String id, String type,
        {double? min, double? max, String unit = '', List<dynamic>? allowed, List<Characteristic>? subs, String? name}) =>
    Characteristic(id, name ?? id, type, min, max, null, subs, unit, allowed);

Characteristic _hsb({double bMax = 254}) => _char(
      'urn:infai:ses:characteristic:70dfbf7f-372f-485d-9486-8ce41da8e91c',
      ContentVariable.structure,
      subs: [
        _char('h', ContentVariable.integer, min: 0, max: 360),
        _char('s', ContentVariable.integer, min: 0, max: 100),
        _char('b', ContentVariable.integer, min: 0, max: bMax),
      ],
    );

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  /// A concept of one base characteristic with its getter and setter.
  void register(String name, String getId, String setId, Characteristic base) {
    final s = AppState();
    s.platformFunctions[getId] = PlatformFunction(getId, 'Get-$name', 'concept-$name', 'Get-$name');
    s.platformFunctions[setId] = PlatformFunction(setId, 'Set-$name', 'concept-$name', 'Set-$name');
    s.concepts['concept-$name'] = Concept('concept-$name', name, base.id, [base]);
  }

  void registerAll({Characteristic? colour, Characteristic? temperature}) {
    final f = AppState().platformFunctions;
    f[onOffFunction] = PlatformFunction(onOffFunction, 'Get-Binary State', 'concept-on-off', 'Get-Binary State');
    f[setOnFunction] = PlatformFunction(setOnFunction, 'Set-On', '', 'Set Device On');
    f[setOffFunction] = PlatformFunction(setOffFunction, 'Set-Off', '', 'Set Device Off');
    register('Brightness', _getBrightness, setBrightnessFunctionId!, _char('char-level', ContentVariable.integer, min: 0, max: 254));
    register('Color Temperature', _getTemperatureColour, setColourTemperatureFunctionId!,
        temperature ?? _char(Characteristics.kelvin, ContentVariable.float, unit: 'K'));
    register('Color', dotenv.env['FUNCTION_GET_COLOR']!, dotenv.env['FUNCTION_SET_COLOR']!, colour ?? _hsb());
    register('Temperature', _getTemperature, _setTemperature, _char(_celsiusId, ContentVariable.float, min: -273.15, unit: '°C'));
    register('Energy', _getEnergy, '$controllingFunctionPrefix:set-energy', _char('char-kwh', ContentVariable.float, unit: 'kWh'));
    for (final name in ['Device', 'Button', 'Heating', 'Air', 'Indoor', 'Reading', 'Target', 'Lighting']) {
      AppState().aspects[name.toLowerCase()] = Aspect(name.toLowerCase(), name, null);
    }
    // A config built before the concepts were there has no characteristic.
    reinit();
  }

  DeviceInstance addDevice() {
    final d = DeviceInstance('dev-1', 'dev-1-local', 'Test device', null, 'type-1', false, 'owner-1', 'Test device',
        DeviceConnectionStatus.online);
    AppState().devices.add(d);
    return d;
  }

  DeviceState state(DeviceInstance? d, String functionId, List<String> aspects, bool controlling, String path,
          {dynamic value, String? characteristicId, String group = 'group-1'}) =>
      DeviceState(value, 'svc-$group', group, functionId, null, controlling, null, null, d?.id, path, group, aspectIds: aspects)
        ..deviceInstance = d
        ..characteristicId = characteristicId;

  /// A Hue-like lamp: switch, brightness, colour temperature and colour, in one
  /// service group on the aspect Lighting.
  DeviceInstance addLamp(
      {dynamic colour, bool colourKnown = true, double? kelvin = 3000, int? brightness = 100, bool on = true}) {
    final d = addDevice();
    const l = ['lighting'];
    d.states
      ..add(state(d, onOffFunction, ['device', 'lighting'], false, 'state', value: on))
      ..add(state(d, setOnFunction, l, true, 'on'))
      ..add(state(d, setOffFunction, l, true, 'off'))
      ..add(state(d, _getBrightness, l, false, 'brightness', value: brightness))
      ..add(state(d, setBrightnessFunctionId!, l, true, 'brightness'))
      ..add(state(d, _getTemperatureColour, l, false, 'color_temp', value: kelvin))
      ..add(state(d, setColourTemperatureFunctionId!, l, true, 'color_temp'))
      ..add(state(d, dotenv.env['FUNCTION_GET_COLOR']!, l, false, 'color', value: colourKnown ? colour ?? {'h': 30, 's': 100, 'b': 100} : null))
      ..add(state(d, dotenv.env['FUNCTION_SET_COLOR']!, l, true, 'color'));
    return d;
  }

  /// A thermostat: setpoint with its control, measured value, heating states.
  /// Without [thermostat] its device type is of another class, as a water
  /// heater's.
  DeviceInstance addThermostat(
      {double setpoint = 22.0, dynamic running = 'idle', dynamic mode = 'heat', bool thermostat = true}) {
    final d = addDevice();
    AppState().deviceTypes['type-1'] =
        DeviceType('type-1', 'Thermostat', '', thermostat ? thermostatDeviceClass : 'class-water-heater', [], null);
    AppState().characteristics['char-off-heat'] =
        _char('char-off-heat', ContentVariable.string, name: 'Binary State (off/heat)', allowed: ['off', 'heat']);
    d.states
      ..add(state(d, onOffFunction, ['heating'], false, 'running_state', value: running, group: 'g-run'))
      ..add(state(d, onOffFunction, ['heating', 'device'], false, 'system_mode',
          value: mode, characteristicId: 'char-off-heat', group: 'g-mode'))
      ..add(state(d, _getTemperature, ['air', 'indoor', 'reading'], false, 'local_temperature', value: 21.5, group: 'g-t'))
      ..add(state(d, _getTemperature, ['target', 'air', 'indoor'], false, 'setpoint', value: setpoint, group: 'g-t'))
      ..add(state(d, _setTemperature, ['target', 'air', 'indoor'], true, 'setpoint', group: 'g-t'));
    return d;
  }

  Future<void> pump(WidgetTester tester, DeviceInstance d, FakeBackend backend) async {
    final values = {for (final s in d.states) s: s.value};
    await pumpGolden(tester, DetailPage(d, null), dark: false);
    values.forEach((s, v) {
      s.value = v;
      s.transitioning = false;
    });
    d.notifyStateChanged();
    await tester.pump();
    serveGoldenBackend(backend);
  }

  FakeBackend answering(dynamic message) {
    final backend = FakeBackend();
    backend.serveJson('POST', batchPath, 200, [
      {'status_code': 200, 'message': message}
    ]);
    return backend;
  }

  List<Map<String, dynamic>> controlsSent(FakeBackend backend) => [
        for (final r in backend.requests.where((r) => r.uri.path == batchPath))
          for (final c in (jsonDecode(r.data as String) as List).cast<Map<String, dynamic>>())
            if ((c['function_id'] as String).startsWith(controllingFunctionPrefix)) c
      ];

  /// Readings of [functionId] arrive in [characteristicId] from now on.
  Future<void> prefer(WidgetTester tester, String functionId, String characteristicId) async {
    await tester.runAsync(() => Settings.setFunctionPreferredCharacteristicId(functionId, characteristicId));
    addTearDown(() => Settings.setFunctionPreferredCharacteristicId(functionId, null));
  }

  /// Adds [c] to the concept called [name], with [conversions] between its
  /// characteristics.
  void addToConcept(String name, Characteristic c, List<ConceptConversion> conversions) {
    final concept = AppState().concepts['concept-$name']!;
    concept.characteristics.add(c);
    concept.conversions = [...?concept.conversions, ...conversions];
    AppState().characteristics[c.id] = c;
  }

  Finder rowWith(String text) => find.ancestor(
      of: find.descendant(of: find.byType(GroupedListTile), matching: find.text(text)), matching: find.byType(GroupedListTile));

  /// Opens the wheel and touches it right of the centre by half the radius:
  /// hue 0, saturation 0.5.
  Future<void> touchWheel(WidgetTester tester) async {
    await tester.tap(find.text('Color'));
    await tester.pump();
    final rect = tester.getRect(find.byType(ColorPickerArea));
    final gesture = await tester.startGesture(rect.center + Offset(rect.width / 4, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
  }

  FilledButton applyButton(WidgetTester tester) => tester.widget<FilledButton>(find.byKey(const Key('colourApply')));

  Future<void> apply(WidgetTester tester) async {
    await tester.runAsync(() async {
      applyButton(tester).onPressed!();
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
  }

  group('label table', () {
    String titleOf(DeviceState s, List<DeviceState> rows) => detailLabel(s, rows, null).title;

    test('a binary state is titled by its aspects, not by the function', () {
      registerAll();
      final heating = state(null, onOffFunction, ['heating'], false, 'a');
      final lighting = state(null, onOffFunction, ['device', 'lighting'], false, 'b');
      final button = state(null, onOffFunction, ['button'], false, 'c');
      final all = [heating, lighting, button];
      expect(detailLabel(heating, all, null), (title: 'Heating', subtitle: ''));
      expect(detailLabel(lighting, all, null), (title: 'Power', subtitle: ''));
      expect(detailLabel(button, all, null), (title: 'Button input', subtitle: ''));
    });

    test('Device alone is Power only on a reading a switch acts on', () {
      registerAll();
      final reading = state(null, onOffFunction, ['device'], false, 'a');
      final on = state(null, setOnFunction, ['device'], true, 'on');
      final off = state(null, setOffFunction, ['device'], true, 'off');
      expect(titleOf(reading, [reading]), 'Binary State', reason: 'nothing switches it');
      expect(detailLabel(reading, [reading, on, off], null).title, 'Power');
    });

    test('heating off/heat is told from idle/heat by the characteristic, not the variable name', () {
      registerAll();
      AppState().characteristics['by-name'] = _char('by-name', ContentVariable.string, name: 'Binary State (off/heat)');
      AppState().characteristics['by-values'] = _char('by-values', ContentVariable.string, name: 'x', allowed: ['off', 'heat']);
      AppState().characteristics['running'] = _char('running', ContentVariable.string, name: 'Binary State (idle/heat)', allowed: []);
      DeviceState heating(String path, String? c) => state(null, onOffFunction, ['heating'], false, path, characteristicId: c);
      expect(binaryRoleOf(heating('running_state', 'by-name'), []), BinaryRole.heatingEnabled);
      expect(binaryRoleOf(heating('running_state', 'by-values'), []), BinaryRole.heatingEnabled);
      expect(binaryRoleOf(heating('system_mode', 'running'), []), BinaryRole.heatingRunning);
      expect(binaryRoleOf(heating('system_mode', null), []), BinaryRole.heatingRunning, reason: 'a group has no characteristic');
    });

    test('value texts of the heating states', () {
      expect(binaryValueText(BinaryRole.heatingRunning, 'heat'), 'Heating');
      expect(binaryValueText(BinaryRole.heatingRunning, 'idle'), 'Idle');
      expect(binaryValueText(BinaryRole.heatingEnabled, 'heat'), 'On');
      expect(binaryValueText(BinaryRole.heatingEnabled, 'off'), 'Off');
      expect(binaryValueText(BinaryRole.power, true), 'On');
      expect(binaryValueText(BinaryRole.button, false), 'Off');
      expect(binaryValueText(BinaryRole.heatingRunning, ['heat', 'heat']), 'Heating');
    });

    test('many values of one function name what they do not all share', () {
      registerAll();
      for (final name in ['Electricity', 'Consumption', 'Generation', 'Phase 1', 'Phase 2', 'Phase 3', 'Total']) {
        AppState().aspects[name] = Aspect(name, name, null);
      }
      AppState().platformFunctions[_getEnergy] = PlatformFunction(_getEnergy, 'Get-Energy', 'concept-Energy', 'Get-Energy');
      final rows = [
        for (final direction in ['Consumption', 'Generation'])
          for (final phase in ['Phase 1', 'Phase 2', 'Phase 3', 'Total'])
            state(null, _getEnergy, ['Electricity', direction, phase], false, '${direction}_$phase'),
      ];
      expect(rows, hasLength(8));
      final label = detailLabel(rows.firstWhere((s) => s.path == 'Consumption_Phase 2'), rows, null);
      expect(label, (title: 'Energy', subtitle: 'Consumption, Phase 2'));
      // The variable's name is for what the aspects leave open.
      expect(detailLabel(rows.firstWhere((s) => s.path == 'Generation_Total'), rows, null).subtitle, 'Generation, Total');
    });
  });

  group('colour values', () {
    test('h/s/b and r/g/b and hex give the colour of their hue and saturation', () {
      expect(colourOf({'h': 30, 's': 100, 'b': 254}), const Color(0xFFFF8000));
      expect(colourOf({'h': 30.0, 's': 100.0, 'b': 0.0}), const Color(0xFFFF8000), reason: 'brightness is its own control');
      expect(colourOf({'r': 255, 'g': 128, 'b': 0}), const Color(0xFFFF8000));
      expect(colourOf('#ff8000'), const Color(0xFFFF8000));
      expect(colourOf({'h': 10}), isNull);
      expect(colourOf(null), isNull);
    });

    test('the layout comes from the characteristic', () {
      final hsb = colourFormatOf(_hsb())!;
      expect((hsb.kind, hsb.brightnessMax, hsb.integers), (ColourKind.hsb, 254.0, true));
      expect(colourFormatOf(_hsb(bMax: 100))!.brightnessMax, 100);
      final rgb = _char('rgb', ContentVariable.structure,
          subs: [for (final n in ['r', 'g', 'b']) _char(n, ContentVariable.integer, min: 0, max: 255)]);
      expect(colourFormatOf(rgb)!.kind, ColourKind.rgb);
      expect(colourFormatOf(_char(Characteristics.hex, ContentVariable.string))!.kind, ColourKind.hex);
      expect(colourFormatOf(_char('x', ContentVariable.float)), isNull);
    });

    test('a chosen hue and saturation are sent at the brightness given', () {
      final hsb = colourFormatOf(_hsb())!;
      expect(colourPayload(120, .5, hsb, brightness: 77 / 254), {'h': 120, 's': 50, 'b': 77});
      expect(colourPayload(120, .5, hsb), {'h': 120, 's': 50, 'b': 254}, reason: 'no brightness known: full');
      expect(colourPayload(30, 1, hsb, brightness: 5 / 254)['h'], isA<int>());
      const rgb = ColourFormat(ColourKind.rgb);
      expect(colourPayload(30, 1, rgb, brightness: 0), {'r': 0, 'g': 0, 'b': 0}, reason: 'a dark colour stays dark');
      expect(colourPayload(30, 1, rgb), {'r': 255, 'g': 128, 'b': 0});
      expect(colourPayload(30, 1, const ColourFormat(ColourKind.hex)), '#ff8000');
    });

    test('without a current colour the lamp brightness stands in', () {
      const hsb = ColourFormat(ColourKind.hsb, brightnessMax: 254, integers: true);
      expect(colourPayload(120, .5, hsb, brightness: .5), {'h': 120, 's': 50, 'b': 127});
      expect(colourPayload(30, 1, const ColourFormat(ColourKind.rgb), brightness: .5), {'r': 128, 'g': 64, 'b': 0});
    });

    test('the brightness of a reading is read in its own layout, the payload built in the control\'s', () {
      final hsb254 = colourFormatOf(_hsb())!, hsb100 = colourFormatOf(_hsb(bMax: 100))!;
      const rgb = ColourFormat(ColourKind.rgb), hex = ColourFormat(ColourKind.hex);
      expect(colourBrightnessOf({'h': 30, 's': 100, 'b': 127}, hsb254), .5);
      expect(colourBrightnessOf({'r': 128, 'g': 64, 'b': 0}, rgb), closeTo(128 / 255, 1e-9));
      expect(colourBrightnessOf('#808080', hex), closeTo(128 / 255, 1e-9));
      expect(colourBrightnessOf({'r': 0, 'g': 0, 'b': 200}, hsb254), isNull, reason: 'the b of r/g/b is blue');
      expect(colourBrightnessOf({'h': 0, 's': 0, 'b': 9}, rgb), isNull);
      expect(colourBrightnessOf({'r': 0, 'g': 0, 'b': 0}, rgb), isNull, reason: 'black says nothing about brightness');
      expect(colourBrightnessOf('#000000', hex), isNull);
      expect(colourBrightnessOf({'h': 30, 's': 100, 'b': 0}, hsb254), isNull);
      expect(colourBrightnessOf(null, hsb254), isNull, reason: 'white mode');
      // A reading on 0..254 and a control on 0..100.
      expect(colourPayload(0, 1, hsb100, brightness: colourBrightnessOf({'h': 0, 's': 100, 'b': 127}, hsb254)),
          {'h': 0, 's': 100, 'b': 50});
      // An r/g/b reading of pure blue is at full value, whatever its b channel says.
      expect(colourPayload(0, 1, hsb254, brightness: colourBrightnessOf({'r': 0, 'g': 0, 'b': 255}, rgb))['b'], 254);
      expect(colourPayload(0, 1, hsb254, brightness: colourBrightnessOf({'h': 0, 's': 1, 'b': 77}, hsb254))['b'], 77,
          reason: 'the same scale gives back the same b');
    });

    test('a config built before the concepts were loaded finds its characteristic later', () {
      registerAll();
      final config = functionConfigs[dotenv.env['FUNCTION_SET_COLOR']]!..characteristic = null;
      expect(configCharacteristic(config.functionId), isNotNull);
    });

    test('a white tone for a colour temperature runs from warm to cold', () {
      final warm = kelvinToColour(2000), cold = kelvinToColour(6500);
      expect(warm.b, lessThan(.2), reason: '2000 K has almost no blue');
      expect(cold.b, greaterThan(.9), reason: '6500 K is near white');
    });
  });

  group('chip', () {
    test('heating states as one chip', () {
      expect(climateChipText(running: 'heat', enabled: 'heat'), 'Heating');
      expect(climateChipText(running: 'idle', enabled: 'heat'), 'Idle');
      expect(climateChipText(running: 'idle', enabled: 'off'), 'Heating off');
      expect(climateChipText(enabled: 'heat'), 'Heating on');
      expect(climateChipText(running: ['heat', 'heat']), 'Heating');
      expect(climateChipText(), isNull);
    });

    test('heating states as booleans and on/off forms', () {
      expect(climateChipText(running: true, enabled: true), 'Heating');
      expect(climateChipText(running: false, enabled: true), 'Idle');
      expect(climateChipText(running: true, enabled: false), 'Heating off');
      expect(climateChipText(enabled: true), 'Heating on');
      expect(climateChipText(running: [true, true]), 'Heating');
      expect(climateChipText(running: 'on'), 'Heating');
      expect(climateChipText(running: 'false'), 'Idle');
      expect(climateChipText(running: 'unknown'), isNull);
      expect(binaryValueText(BinaryRole.heatingRunning, true), 'Heating');
      expect(binaryValueText(BinaryRole.heatingRunning, false), 'Idle');
      expect(binaryValueText(BinaryRole.heatingEnabled, true), 'On');
      expect(binaryValueText(BinaryRole.heatingEnabled, false), 'Off');
    });
  });

  group('which states a card takes', () {
    test('a lamp card covers its switch, readings and controls, not its other rows', () {
      registerAll();
      final d = addLamp();
      final extra = state(d, _getTemperature, ['air'], false, 'internal', value: 30.0);
      d.states.add(extra);
      final model = lightCardOf(d.states, d.states, isGroup: false)!;
      expect(model.power, isNotNull);
      expect([model.brightness, model.temperature, model.colour], everyElement(isNotNull));
      expect(model.covered, hasLength(d.states.length - 1));
      expect(model.covered, isNot(contains(extra)));
    });

    test('a kind whose control has no reading stays a row', () {
      registerAll();
      final d = addLamp();
      d.states.removeWhere((s) => s.functionId == _getBrightness);
      final model = lightCardOf(d.states, d.states, isGroup: false)!;
      expect(model.brightness, isNull);
      expect(model.covered.where((s) => s.functionId == setBrightnessFunctionId!), isEmpty);
    });

    test('a colour in a layout the wheel does not know stays a row', () {
      registerAll(colour: _char('exotic', ContentVariable.structure, subs: [_char('x', ContentVariable.float)]));
      final d = addLamp();
      final model = lightCardOf(d.states, d.states, isGroup: false)!;
      expect(model.colour, isNull);
      expect(model.covered.where((s) => s.functionId == dotenv.env['FUNCTION_SET_COLOR']), isEmpty);
    });

    test('a device without lamp functions has no card', () {
      registerAll();
      final d = addDevice();
      d.states
        ..add(state(d, onOffFunction, ['device'], false, 'a', value: true))
        ..add(state(d, setOnFunction, ['device'], true, 'on'))
        ..add(state(d, setOffFunction, ['device'], true, 'off'));
      expect(lightCardOf(d.states, d.states, isGroup: false), isNull);
    });

    test('a group whose members disagree on a value falls back to rows for that kind', () {
      registerAll();
      DeviceState reading(String f, dynamic v) => state(null, f, ['lighting'], false, 'r$f', value: v)..deviceGroup = null;
      final states = [
        reading(_getBrightness, [100, 200]),
        state(null, setBrightnessFunctionId!, ['lighting'], true, 'c1'),
        reading(_getTemperatureColour, [3000.0, 3000.0]),
        state(null, setColourTemperatureFunctionId!, ['lighting'], true, 'c2'),
      ];
      final model = lightCardOf(states, states, isGroup: true)!;
      expect(model.brightness, isNull, reason: '100 and 200 have no common value');
      expect(model.temperature, isNotNull);
    });

    test('a lamp whose on/off value is unknown keeps the switch and its controls as rows', () {
      registerAll();
      final d = addLamp();
      final power = d.states.firstWhere((s) => s.functionId == onOffFunction)..value = null;
      final model = lightCardOf(d.states, d.states, isGroup: false)!;
      expect(model.power, isNull);
      expect(model.covered, isNot(contains(power)));
      expect(model.covered.where((s) => s.functionId == setOnFunction || s.functionId == setOffFunction), isEmpty);
      power.transitioning = true;
      expect(lightCardOf(d.states, d.states, isGroup: false)!.power, power,
          reason: 'while it loads the card keeps it, with a spinner');
    });

    test('brightness or colour temperature without a start value stays a row, unless it is loading', () {
      registerAll();
      final d = addLamp(brightness: null, kelvin: null);
      final model = lightCardOf(d.states, d.states, isGroup: false)!;
      expect(model.brightness, isNull);
      expect(model.temperature, isNull);
      expect(model.colour, isNotNull);
      for (final s in d.states.where((s) => s.functionId == _getBrightness)) {
        s.transitioning = true;
      }
      expect(lightCardOf(d.states, d.states, isGroup: false)!.brightness, isNotNull);
    });

    test('a group whose members report nothing has no start value either', () {
      registerAll();
      final states = [
        state(null, _getBrightness, ['lighting'], false, 'r', value: [null, null]),
        state(null, setBrightnessFunctionId!, ['lighting'], true, 'c'),
        state(null, _getTemperatureColour, ['lighting'], false, 'r2', value: [3000.0, null]),
        state(null, setColourTemperatureFunctionId!, ['lighting'], true, 'c2'),
      ];
      final model = lightCardOf(states, states, isGroup: true)!;
      expect(model.brightness, isNull);
      expect(model.temperature, isNotNull, reason: 'one member without a value does not disagree');
    });

    test('a setpoint without a value has no card, unless it is loading', () {
      registerAll();
      final d = addThermostat();
      final setpoint = d.states.firstWhere((s) => s.path == 'setpoint' && !s.isControlling)..value = null;
      expect(climateCardsOf(d.states, d.states, isGroup: false), isEmpty);
      setpoint.transitioning = true;
      expect(climateCardsOf(d.states, d.states, isGroup: false), hasLength(1), reason: 'loading');
    });

    test('a thermostat card takes setpoint, measurement and heating states', () {
      registerAll();
      final d = addThermostat();
      // Listed first, without the aspect Reading: it must not be taken as the measurement.
      final internal = state(d, _getTemperature, ['air'], false, 'internal', value: 30.0, group: 'g-i');
      d.states.insert(0, internal);
      final cards = climateCardsOf(d.states, d.states, isGroup: false);
      expect(cards, hasLength(1));
      final c = cards.single;
      expect(c.covered, isNot(contains(internal)));
      expect(c.setpoint.path, 'setpoint');
      expect(c.measured!.path, 'local_temperature');
      expect(c.heating.map((s) => s.path), unorderedEquals(['running_state', 'system_mode']));
      expect(c.covered, hasLength(d.states.length - 1));
    });
  });

  group('detail page', () {
    testWidgets('a lamp is one card with switch, sliders and colour, and no rows below it', (tester) async {
      registerAll();
      final d = addLamp();
      await pump(tester, d, answering([1]));

      expect(find.byType(LightCard), findsOneWidget);
      expect(find.text('Readings'), findsNothing);
      expect(find.text('Brightness'), findsOneWidget, reason: 'not repeated as a row');
      expect(find.text('Power'), findsNothing);
      expect(find.byType(Switch), findsOneWidget);
      expect(tester.widgetList<Slider>(find.byType(Slider)), hasLength(2));
      expect(find.text('3000 K'), findsOneWidget);
      expect(find.byType(ColorPickerArea), findsNothing, reason: 'the wheel opens on tap');
      // The swatch shows the lamp's colour: hue 30 at full saturation.
      final swatch = tester.widget<Container>(find.byKey(const Key('lightSwatch')));
      expect((swatch.decoration as BoxDecoration).color, const Color(0xFFFF8000));
    });

    testWidgets('colour temperature is a slider of 2000 to 6500 K that sends Kelvin', (tester) async {
      registerAll();
      final d = addLamp();
      final backend = answering([3500.0]);
      await pump(tester, d, backend);

      final slider = tester.widgetList<Slider>(find.byType(Slider)).firstWhere((s) => s.max == 6500);
      expect((slider.min, slider.value), (2000.0, 3000.0));
      await tester.runAsync(() async {
        slider.onChangeEnd!(3500);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      final sent = controlsSent(backend);
      expect(sent, hasLength(1));
      expect(sent.single['function_id'], setColourTemperatureFunctionId!);
      expect(sent.single['input'], 3500.0);
    });

    testWidgets('colour temperature outside a card is the same slider', (tester) async {
      registerAll();
      final d = addDevice();
      // Two controls of one kind are no card's: each stays a row.
      for (final group in ['g1', 'g2']) {
        d.states
          ..add(state(d, _getTemperatureColour, ['lighting'], false, 'color_temp', value: 4000.0, group: group))
          ..add(state(d, setColourTemperatureFunctionId!, ['lighting'], true, 'color_temp', group: group));
      }
      await pump(tester, d, answering([1]));

      expect(find.byType(LightCard), findsNothing);
      final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
      expect(sliders, hasLength(2));
      expect((sliders.first.min, sliders.first.max, sliders.first.value), (2000.0, 6500.0, 4000.0));
    });

    testWidgets('the wheel only moves a draft; Apply sends it once, with the lamp brightness kept', (tester) async {
      registerAll();
      final d = addLamp(colour: {'h': 30, 's': 100, 'b': 77});
      final backend = answering([
        {'h': 0, 's': 50, 'b': 77}
      ]);
      await pump(tester, d, backend);

      await tester.tap(find.text('Color'));
      await tester.pump();
      expect(applyButton(tester).onPressed, isNull, reason: 'nothing chosen yet');
      final rect = tester.getRect(find.byType(ColorPickerArea));
      final gesture = await tester.startGesture(rect.center + Offset(rect.width / 4, 0));
      await tester.pump();
      await tester.runAsync(() async {
        await gesture.up();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      expect(backend.requests, isEmpty, reason: 'touching the wheel sends nothing');
      final draft = tester.widget<Container>(find.byKey(const Key('colourDraftSwatch')));
      expect(HSVColor.fromColor((draft.decoration as BoxDecoration).color!).hue, closeTo(0, 1));

      await apply(tester);
      final sent = controlsSent(backend);
      expect(sent, hasLength(1));
      expect(sent.single['function_id'], dotenv.env['FUNCTION_SET_COLOR']);
      final input = sent.single['input'] as Map<String, dynamic>;
      expect(input['b'], 77, reason: 'brightness is kept');
      expect(input['h'], 0);
      expect(input['s'], inInclusiveRange(48, 52));
      expect(input['h'], isA<int>());
      expect(applyButton(tester).onPressed, isNull, reason: 'the draft is gone once sent');
    });

    testWidgets('Apply is disabled while the colour is being set', (tester) async {
      registerAll();
      final d = addLamp();
      await pump(tester, d, answering([1]));
      await touchWheel(tester);
      expect(applyButton(tester).onPressed, isNotNull);
      d.states.firstWhere((s) => s.path == 'color' && !s.isControlling).transitioning = true;
      d.notifyStateChanged();
      await tester.pump();
      expect(applyButton(tester).onPressed, isNull);
    });

    testWidgets('a lamp in white mode reports no colour and can still be given one', (tester) async {
      registerAll();
      // Brightness 100 of 0..254: the colour is sent at that share.
      final d = addLamp(colourKnown: false, brightness: 100);
      final backend = answering([
        {'h': 0, 's': 50, 'b': 100}
      ]);
      await pump(tester, d, backend);
      await touchWheel(tester);
      await apply(tester);

      final sent = controlsSent(backend);
      expect(sent, hasLength(1));
      expect((sent.single['input'] as Map)['b'], 100, reason: 'the lamp brightness, not full');
    });

    testWidgets('white mode with brightness shown in percent: the share is that of the control\'s range', (tester) async {
      registerAll();
      addToConcept('Brightness', _char('char-pct', ContentVariable.float, min: 0, max: 100, unit: '%'), [
        ConceptConversion('char-level', 'char-pct', 1, 'x * 100 / 254', 'x'),
        ConceptConversion('char-pct', 'char-level', 1, 'x * 254 / 100', 'x'),
      ]);
      await prefer(tester, _getBrightness, 'char-pct');
      final d = addLamp(colourKnown: false, brightness: 50);
      final backend = answering([
        {'h': 0, 's': 50, 'b': 127}
      ]);
      await pump(tester, d, backend);

      final slider = tester.widgetList<Slider>(find.byType(Slider)).firstWhere((s) => s.max == 254);
      expect(slider.value, 127, reason: '50 % of 0..254');
      await touchWheel(tester);
      await apply(tester);
      expect((controlsSent(backend).single['input'] as Map)['b'], 127);
    });

    testWidgets('a colour reading on another brightness scale than the control keeps the lamp as bright', (tester) async {
      registerAll();
      final hsb100 = _char('hsb100', ContentVariable.structure, subs: [
        _char('h', ContentVariable.integer, min: 0, max: 360),
        _char('s', ContentVariable.integer, min: 0, max: 100),
        _char('b', ContentVariable.integer, min: 0, max: 100),
      ]);
      addToConcept('Color', hsb100, const []);
      await prefer(tester, dotenv.env['FUNCTION_GET_COLOR']!, 'hsb100');
      final d = addLamp(colour: {'h': 30, 's': 100, 'b': 50});
      final backend = answering([
        {'h': 0, 's': 50, 'b': 127}
      ]);
      await pump(tester, d, backend);
      await touchWheel(tester);
      await apply(tester);
      expect((controlsSent(backend).single['input'] as Map)['b'], 127, reason: 'b 50 of 100 is 127 of 254');
    });

    testWidgets('colour temperature read in mired and set in Kelvin starts from the Kelvin value', (tester) async {
      registerAll();
      addToConcept('Color Temperature', _char(miredCharacteristicId, ContentVariable.float, unit: 'mired'), [
        ConceptConversion(miredCharacteristicId, Characteristics.kelvin, 1, '1000000 / x', 'x'),
        ConceptConversion(Characteristics.kelvin, miredCharacteristicId, 1, '1000000 / x', 'x'),
      ]);
      await prefer(tester, _getTemperatureColour, miredCharacteristicId);
      final d = addLamp(kelvin: 250, colour: {'h': 0, 's': 0, 'b': 100});
      await pump(tester, d, answering([1]));

      final slider = tester.widgetList<Slider>(find.byType(Slider)).firstWhere((s) => s.max == 6500);
      expect(slider.value, 4000, reason: '250 mired');
      final swatch = tester.widget<Container>(find.byKey(const Key('lightSwatch')));
      expect((swatch.decoration as BoxDecoration).color, kelvinToColour(4000));
    });

    testWidgets('a lamp with an unknown on/off value can still be switched, by its rows', (tester) async {
      registerAll();
      final d = addLamp();
      await pump(tester, d, answering([true]));
      d.states.firstWhere((s) => s.functionId == onOffFunction).value = null;
      d.notifyStateChanged();
      await tester.pump();

      expect(find.byType(LightCard), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
      for (final title in ['Set Device On', 'Set Device Off']) {
        final button = tester.widget<IconButton>(find.descendant(of: rowWith(title), matching: find.byType(IconButton)));
        expect(button.onPressed, isNotNull, reason: title);
      }
    });

    testWidgets('a thermostat is one card: measured value large, chip, setpoint stepper', (tester) async {
      registerAll();
      final d = addThermostat();
      final backend = answering([22.5]);
      await pump(tester, d, backend);

      expect(find.byType(ClimateCard), findsOneWidget);
      expect(find.text('Readings'), findsNothing);
      expect(find.text('21.5 °C'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('climateChip')), matching: find.text('Idle')), findsOneWidget);
      expect(find.text('Target Temperature'), findsOneWidget);
      expect(find.text('22 °C'), findsOneWidget);
      expect(find.text('Heating enabled'), findsNothing, reason: 'covered by the chip');

      await tester.runAsync(() async {
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add)).onPressed!();
        await Future<void>.delayed(const Duration(milliseconds: 1100));
      });
      await tester.pump();
      final sent = controlsSent(backend);
      expect(sent, hasLength(1));
      expect(sent.single['input'], 22.5);
    });

    testWidgets('a thermostat without a setpoint value keeps its dialog row', (tester) async {
      registerAll();
      final d = addThermostat();
      await pump(tester, d, answering([1]));
      d.states.firstWhere((s) => s.path == 'setpoint' && !s.isControlling).value = null;
      d.notifyStateChanged();
      await tester.pump();

      expect(find.byType(ClimateCard), findsNothing);
      expect(find.widgetWithIcon(IconButton, Icons.add), findsNothing);
      final dialog = tester.widget<TextButton>(find.descendant(of: rowWith('Target Temperature'), matching: find.byType(TextButton)));
      expect(dialog.onPressed, isNotNull);
    });

    testWidgets('a setpoint read in Fahrenheit and set in Celsius steps from the Celsius value', (tester) async {
      registerAll();
      addToConcept('Temperature', _char('char-fahrenheit', ContentVariable.float, unit: '°F'), [
        ConceptConversion(_celsiusId, 'char-fahrenheit', 1, 'x * 9 / 5 + 32', 'x'),
        ConceptConversion('char-fahrenheit', _celsiusId, 1, '(x - 32) * 5 / 9', 'x'),
      ]);
      await prefer(tester, _getTemperature, 'char-fahrenheit');
      final d = addThermostat(setpoint: 68.0);
      final backend = answering([66.2]);
      await pump(tester, d, backend);

      expect(find.byType(ClimateCard), findsOneWidget);
      expect(find.text('20 °C'), findsOneWidget, reason: '68 °F in the control\'s unit');
      await tester.runAsync(() async {
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.remove)).onPressed!();
        await Future<void>.delayed(const Duration(milliseconds: 1100));
      });
      await tester.pump();
      final sent = controlsSent(backend);
      expect(sent, hasLength(1));
      expect(sent.single['input'], 19.5);
    });

    testWidgets('a setpoint in a unit with no conversion to the control\'s has no card and keeps its dialog', (tester) async {
      registerAll();
      addToConcept('Temperature', _char('char-fahrenheit', ContentVariable.float, unit: '°F'), const []);
      await prefer(tester, _getTemperature, 'char-fahrenheit');
      final d = addThermostat(setpoint: 68.0);
      await pump(tester, d, answering([1]));

      expect(find.byType(ClimateCard), findsNothing);
      expect(find.widgetWithIcon(IconButton, Icons.remove), findsNothing);
      expect(find.descendant(of: rowWith('Target Temperature'), matching: find.byType(TextButton)), findsOneWidget);
    });

    testWidgets('the setpoint of a thermostat stops at 30 degrees', (tester) async {
      registerAll();
      final d = addThermostat(setpoint: 30.0);
      await pump(tester, d, answering([30.0]));
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add)).onPressed, isNull);
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.remove)).onPressed, isNotNull);
    });

    testWidgets('a setpoint of another device is held only to its characteristic', (tester) async {
      registerAll();
      final d = addThermostat(setpoint: 55.0, thermostat: false);
      final backend = answering([54.5]);
      await pump(tester, d, backend);

      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add)).onPressed, isNotNull,
          reason: 'a water heater sets far above 30 degrees');
      await tester.runAsync(() async {
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.remove)).onPressed!();
        await Future<void>.delayed(const Duration(milliseconds: 1100));
      });
      await tester.pump();
      expect(controlsSent(backend).map((c) => c['input']), [54.5]);
    });

    testWidgets('the external temperature input steps from the measured value it feeds', (tester) async {
      registerAll();
      final d = addThermostat();
      d.states.add(state(d, _setTemperature, ['air', 'indoor', 'reading'], true, 'external_temperature_input', group: 'g-t'));
      final backend = answering([22.0]);
      await pump(tester, d, backend);

      final row = rowWith('External temperature input');
      expect(find.descendant(of: row, matching: find.text('21.5 °C')), findsOneWidget);
      await tester.runAsync(() async {
        tester.widget<IconButton>(find.descendant(of: row, matching: find.widgetWithIcon(IconButton, Icons.add))).onPressed!();
        await Future<void>.delayed(const Duration(milliseconds: 1100));
      });
      await tester.pump();
      final sent = controlsSent(backend);
      expect(sent.map((c) => c['input']), [22.0]);
      expect(sent.single['aspect_ids'], ['air', 'indoor', 'reading']);
    });

    testWidgets('a switched-off heating shows as a chip text', (tester) async {
      registerAll();
      final d = addThermostat(mode: 'off');
      await pump(tester, d, answering([22.0]));
      expect(find.descendant(of: find.byKey(const Key('climateChip')), matching: find.text('Heating off')), findsOneWidget);
    });

    testWidgets('boolean heating states show in the chip', (tester) async {
      registerAll();
      final d = addThermostat(running: true, mode: true);
      await pump(tester, d, answering([22.0]));
      expect(find.byType(ClimateCard), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('climateChip')), matching: find.text('Heating')), findsOneWidget);
    });

    testWidgets('a heating state with an unknown value stays a row', (tester) async {
      registerAll();
      final d = addThermostat(running: 'unexpected');
      await pump(tester, d, answering([22.0]));
      expect(find.byType(ClimateCard), findsOneWidget);
      expect(find.descendant(of: rowWith('Heating'), matching: find.text('Unexpected')), findsOneWidget);
    });
  });
}
