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
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/config/functions/function_config.dart';
import 'package:mobile_app/models/aspect.dart';
import 'package:mobile_app/models/characteristic.dart';
import 'package:mobile_app/models/concept.dart';
import 'package:mobile_app/models/content_variable.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/live/conversion/casts.dart' show Characteristics;
import 'package:mobile_app/models/function.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/widgets/shared/grouped_list_tile.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/detail_page.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/inline_control.dart';
import 'package:mobile_app/widgets/tabs/shared/device_state_action.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';
import 'sensor_switch_fixture.dart';

const _getLevel = 'urn:infai:ses:measuring-function:level';
const _setLevel = '$controllingFunctionPrefix:set-level';
const _getMired = 'urn:infai:ses:measuring-function:mired';
const _setMired = '$controllingFunctionPrefix:set-mired';
const _getTemp = 'urn:infai:ses:measuring-function:temperature';
const _setTemp = '$controllingFunctionPrefix:set-temperature';
const _getMode = 'urn:infai:ses:measuring-function:mode';
const _setMode = '$controllingFunctionPrefix:set-mode';
const _getColor = 'urn:infai:ses:measuring-function:colour';
const _setColor = '$controllingFunctionPrefix:set-colour';
const _getKelvin = 'urn:infai:ses:measuring-function:kelvin';
const _setKelvin = '$controllingFunctionPrefix:set-kelvin';
const _getWhite = 'urn:infai:ses:measuring-function:white';
const _setWhite = '$controllingFunctionPrefix:set-white';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  Characteristic char(String id, String type,
          {double? min, double? max, String unit = '', List<dynamic>? allowed, List<Characteristic>? subs}) =>
      Characteristic(id, id, type, min, max, null, subs, unit, allowed);

  /// A concept of one base characteristic with its getter and setter.
  void register(String name, String getId, String setId, Characteristic base) {
    final s = AppState();
    s.platformFunctions[getId] = PlatformFunction(getId, 'Get-$name', 'concept-$name', 'Get-$name');
    s.platformFunctions[setId] = PlatformFunction(setId, 'Set-$name', 'concept-$name', 'Set-$name');
    s.concepts['concept-$name'] = Concept('concept-$name', name, base.id, [base]);
  }

  void registerAll({List<dynamic>? modes}) {
    registerOnOffFunctions();
    AppState().platformFunctions[onOffFunction] =
        PlatformFunction(onOffFunction, 'Get-Binary State', 'concept-on-off', 'Get-Binary State');
    register('Brightness', _getLevel, _setLevel,
        char('char-level', ContentVariable.integer, min: 0, max: 254));
    register('Mired', _getMired, _setMired, char('char-mired', ContentVariable.float, min: 0, unit: 'K'));
    register('Temperature', _getTemp, _setTemp,
        char('char-celsius', ContentVariable.float, min: -273.15, unit: '°C'));
    register('Mode', _getMode, _setMode, char('char-mode', ContentVariable.string, allowed: modes));
    register(
        'Colour',
        _getColor,
        _setColor,
        char('char-hsb', ContentVariable.structure,
            subs: [char('h', ContentVariable.float, min: 0, max: 360), char('s', ContentVariable.float, min: 0, max: 100)]));
    // Kelvin as a temperature, in a concept that lists Celsius too, and as the
    // tone of a white light, in one that does not.
    register('Kelvin', _getKelvin, _setKelvin, char(Characteristics.kelvin, ContentVariable.float, unit: 'K'));
    AppState().concepts['concept-Kelvin']!.characteristics.add(char(Characteristics.celsius, ContentVariable.float, unit: '°C'));
    register('White', _getWhite, _setWhite, char(Characteristics.kelvin, ContentVariable.float, unit: 'K'));
    for (final name in ['Lighting', 'Target']) {
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

  DeviceState state(DeviceInstance? d, String functionId, bool controlling, String path, {dynamic value}) =>
      DeviceState(value, 'svc-$path', 'group-1', functionId, null, controlling, null, null, d?.id, path, 'group-1',
          aspectIds: const ['lighting'])
        ..deviceInstance = d;

  /// Mounts the page without a backend, so its own load fails, then sets the
  /// readings and serves [backend].
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

  List<Map<String, dynamic>> sent(FakeBackend backend) => [
        for (final r in backend.requests.where((r) => r.uri.path == batchPath))
          ...(jsonDecode(r.data as String) as List).cast<Map<String, dynamic>>()
      ];

  List<Map<String, dynamic>> controlsSent(FakeBackend backend) =>
      sent(backend).where((c) => (c['function_id'] as String).startsWith(controllingFunctionPrefix)).toList();

  Finder rowWith(String text) => find.ancestor(
      of: find.descendant(of: find.byType(GroupedListTile), matching: find.text(text)), matching: find.byType(GroupedListTile));

  group('which control a row gets', () {
    DeviceState control(String functionId) => state(null, functionId, true, 'c');

    test('a range is a slider, as for the Android controls', () {
      registerAll();
      final spec = inlineControlSpec(control(_setLevel), 100)!;
      expect(spec.kind, InlineControlKind.slider);
      expect((spec.min, spec.max, spec.integer), (0.0, 254.0, true));
    });

    test('a temperature without a range is a stepper, held to the bounds it has', () {
      registerAll();
      final celsius = inlineControlSpec(control(_setTemp), 21.5)!;
      expect(celsius.kind, InlineControlKind.stepper);
      expect((celsius.min, celsius.max, celsius.step), (-273.15, null, 0.5));
      expect(inlineControlSpec(control(_setKelvin), 290.0)?.kind, InlineControlKind.stepper, reason: 'Kelvin of a temperature');
    });

    test('any other number without a range keeps the dialog, unless it is a setpoint', () {
      registerAll();
      expect(inlineControlSpec(control(_setMired), 300.0), isNull);
      expect(inlineControlSpec(control(_setWhite), 3000.0), isNull, reason: 'Kelvin of a colour temperature');
      final target = DeviceState(null, 'svc', 'group-1', _setMired, null, true, null, null, null, 'c', 'group-1',
          aspectIds: const ['target']);
      expect(inlineControlSpec(target, 300.0)?.kind, InlineControlKind.stepper);
      final reading = DeviceState(300.0, 'svc', 'group-1', _getMired, null, false, null, null, null, 'r', 'group-1',
          aspectIds: const ['target']);
      expect(inlineControlSpec(control(_setMired), 300.0, reading: reading)?.kind, InlineControlKind.stepper);
    });

    test('a number with no start value stays a dialog', () {
      registerAll();
      expect(inlineControlSpec(control(_setLevel), null), isNull);
      expect(inlineControlSpec(control(_setTemp), null), isNull);
    });

    test('allowed values are segments up to four, else a dropdown', () {
      registerAll(modes: ['a', 'b', 'c', 'd']);
      expect(inlineControlSpec(control(_setMode), 'a')!.kind, InlineControlKind.choice);
      registerAll(modes: ['a', 'b', 'c', 'd', 'e']);
      expect(inlineControlSpec(control(_setMode), 'a')!.kind, InlineControlKind.dropdown);
      expect(inlineControlSpec(control(_setMode), null)!.kind, InlineControlKind.dropdown,
          reason: 'no start value, no selection, still settable');
    });

    test('a structure or free text stays a dialog', () {
      registerAll();
      expect(inlineControlSpec(control(_setColor), {'h': 1, 's': 2}), isNull);
      expect(inlineControlSpec(control(_setMode), 'a'), isNull, reason: 'no allowed values');
    });

    test('a group starts from the value its devices share, as the dialog does', () {
      registerAll();
      DeviceState reading(dynamic v) => state(null, _getLevel, false, 'r', value: v);
      final c = control(_setLevel);
      expect(controlStartValue(c, [reading([100, 100]), c], isGroup: true), 100);
      expect(controlStartValue(c, [reading([100, 120]), c], isGroup: true), isNull);
      expect(controlStartValue(c, [reading(100), c], isGroup: false), 100);
    });
  });

  group('detail page', () {
    testWidgets('a slider sends once, on release, the value the dialog would send', (tester) async {
      registerAll();
      final d = addDevice();
      d.states
        ..add(state(d, _getLevel, false, 'brightness', value: 100))
        ..add(state(d, _setLevel, true, 'brightness'));
      final backend = answering([150]);
      await pump(tester, d, backend);

      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.value, 100);
      expect(find.byType(TextButton), findsNothing, reason: 'no dialog button');

      await tester.runAsync(() async {
        slider.onChanged!(120);
        slider.onChanged!(150);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(backend.requests, isEmpty, reason: 'dragging sends nothing');
        slider.onChangeEnd!(150);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      final controls = controlsSent(backend);
      expect(controls, hasLength(1));
      expect(controls.single['function_id'], _setLevel);
      expect(controls.single['input'], 150);
      expect(controls.single['input'], isA<int>(), reason: 'an integer characteristic sends an integer');
      expect(sent(backend).map((c) => c['function_id']), [_setLevel, _getLevel], reason: 'the read-back follows');
      expect(d.states.first.value, 150);
    });

    testWidgets('a slider of a busy row is disabled', (tester) async {
      registerAll();
      final d = addDevice();
      final reading = state(d, _getLevel, false, 'brightness', value: 100);
      d.states
        ..add(reading)
        ..add(state(d, _setLevel, true, 'brightness'));
      await pump(tester, d, answering([1]));

      reading.transitioning = true;
      d.notifyStateChanged();
      await tester.pump();
      // Past the delay of the spinner's own timer.
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
      expect(tester.widget<Slider>(find.byType(Slider)).onChangeEnd, isNull);
    });

    testWidgets('a stepper sends once, 800 ms after the last tap', (tester) async {
      registerAll();
      final d = addDevice();
      d.states
        ..add(state(d, _getTemp, false, 'setpoint', value: 21.0))
        ..add(state(d, _setTemp, true, 'setpoint'));
      final backend = answering([23.0]);
      await pump(tester, d, backend);

      expect(find.text('21 °C'), findsOneWidget);
      IconButton plus() => tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add));

      await tester.runAsync(() async {
        plus().onPressed!();
        plus().onPressed!();
        plus().onPressed!();
        plus().onPressed!();
        await Future<void>.delayed(const Duration(milliseconds: 500));
        expect(backend.requests, isEmpty, reason: 'still inside the debounce window');
        await Future<void>.delayed(const Duration(milliseconds: 600));
      });
      await tester.pump();

      final controls = controlsSent(backend);
      expect(controls, hasLength(1), reason: 'four taps, one command');
      expect(controls.single['input'], 23.0);
      expect(controls.single['input'], isA<double>());
      expect(d.states.first.value, 23.0);
    });

    testWidgets('a stepper stops at the minimum the characteristic has', (tester) async {
      registerAll();
      final d = addDevice();
      d.states
        ..add(state(d, _getTemp, false, 'temperature', value: -273.15))
        ..add(state(d, _setTemp, true, 'temperature'));
      await pump(tester, d, answering([0]));

      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.remove)).onPressed, isNull);
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add)).onPressed, isNotNull);
    });

    testWidgets('a number without a range that is no temperature keeps the dialog button with its value', (tester) async {
      registerAll();
      final d = addDevice();
      d.states
        ..add(state(d, _getMired, false, 'mired', value: 286.0))
        ..add(state(d, _setMired, true, 'mired'));
      await pump(tester, d, answering([1]));

      expect(find.widgetWithIcon(IconButton, Icons.add), findsNothing);
      expect(find.widgetWithText(TextButton, '286 K'), findsOneWidget);
    });

    testWidgets('a reading shown in another unit is stepped from its value in the control\'s unit', (tester) async {
      registerAll();
      AppState().concepts['concept-Temperature']!
        ..characteristics.add(char('char-f', ContentVariable.float, unit: '°F'))
        ..conversions = [
          ConceptConversion('char-celsius', 'char-f', 1, 'x * 9 / 5 + 32', 'x'),
          ConceptConversion('char-f', 'char-celsius', 1, '(x - 32) * 5 / 9', 'x'),
        ];
      await tester.runAsync(() => Settings.setFunctionPreferredCharacteristicId(_getTemp, 'char-f'));
      addTearDown(() => Settings.setFunctionPreferredCharacteristicId(_getTemp, null));
      final d = addDevice();
      d.states
        ..add(state(d, _getTemp, false, 'temperature', value: 68.0))
        ..add(state(d, _setTemp, true, 'temperature'));
      final backend = answering([69.8]);
      await pump(tester, d, backend);

      expect(find.text('20 °C'), findsOneWidget);
      await tester.runAsync(() async {
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add)).onPressed!();
        await Future<void>.delayed(const Duration(milliseconds: 1100));
      });
      await tester.pump();
      expect(controlsSent(backend).single['input'], 20.5);
    });

    testWidgets('a reading in a unit with no conversion to the control\'s keeps the dialog', (tester) async {
      registerAll();
      AppState().concepts['concept-Temperature']!.characteristics.add(char('char-f', ContentVariable.float, unit: '°F'));
      AppState().characteristics['char-f'] = char('char-f', ContentVariable.float, unit: '°F');
      await tester.runAsync(() => Settings.setFunctionPreferredCharacteristicId(_getTemp, 'char-f'));
      addTearDown(() => Settings.setFunctionPreferredCharacteristicId(_getTemp, null));
      final d = addDevice();
      d.states
        ..add(state(d, _getTemp, false, 'temperature', value: 68.0))
        ..add(state(d, _setTemp, true, 'temperature'));
      await pump(tester, d, answering([1]));

      expect(find.widgetWithIcon(IconButton, Icons.add), findsNothing);
      expect(find.widgetWithText(TextButton, '68 °F'), findsOneWidget);
    });

    testWidgets('the dialog of a reading in a unit with no conversion starts empty, not with the foreign number', (tester) async {
      registerAll();
      AppState().concepts['concept-Temperature']!.characteristics.add(char('char-f', ContentVariable.float, unit: '°F'));
      AppState().characteristics['char-f'] = char('char-f', ContentVariable.float, unit: '°F');
      await tester.runAsync(() => Settings.setFunctionPreferredCharacteristicId(_getTemp, 'char-f'));
      addTearDown(() => Settings.setFunctionPreferredCharacteristicId(_getTemp, null));
      final d = addDevice();
      d.states
        ..add(state(d, _getTemp, false, 'temperature', value: 68.0))
        ..add(state(d, _setTemp, true, 'temperature'));
      await pump(tester, d, answering([1]));

      await tester.tap(find.widgetWithText(TextButton, '68 °F'));
      await tester.pumpAndSettle();
      expect(find.text('Configure'), findsOneWidget);
      final texts = tester
          // The page itself has no text field, so every one is the dialog's.
          .widgetList<EditableText>(find.byType(EditableText))
          .map((e) => e.controller.text)
          .toList();
      expect(texts, isNotEmpty);
      expect(texts.join(), isNot(contains('68')), reason: '68 would be sent as 68 °C');
    });

    testWidgets('a stepper change pending when the page closes is sent, once', (tester) async {
      registerAll();
      final d = addDevice();
      d.states
        ..add(state(d, _getTemp, false, 'setpoint', value: 21.0))
        ..add(state(d, _setTemp, true, 'setpoint'));
      final backend = answering([21.5]);
      await pump(tester, d, backend);

      await tester.runAsync(() async {
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add)).onPressed!();
      });
      await tester.pumpWidget(const SizedBox());
      // The command started in the test's fake zone; let both clocks run.
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 100));
      }

      final controls = controlsSent(backend);
      expect(controls, hasLength(1));
      expect(controls.single['input'], 21.5);
    });

    testWidgets('a stepper on a converted value first goes to the step grid', (tester) async {
      registerAll();
      for (final (label, icon, expected) in [('plus', Icons.add, 20.5), ('minus', Icons.remove, 20.0)]) {
        resetAppStateForGolden();
        resetGoldenBackend();
        registerAll();
        final d = addDevice();
        d.states
          ..add(state(d, _getTemp, false, 'setpoint', value: 20.2778))
          ..add(state(d, _setTemp, true, 'setpoint'));
        final backend = answering([expected]);
        await pump(tester, d, backend);

        await tester.runAsync(() async {
          tester.widget<IconButton>(find.widgetWithIcon(IconButton, icon)).onPressed!();
          await Future<void>.delayed(const Duration(milliseconds: 1100));
        });
        await tester.pump();

        expect(controlsSent(backend).single['input'], expected, reason: label);
      }
    });

    testWidgets('a stepper change pending when the page closes does not notify during the locked phase', (tester) async {
      registerAll();
      final d = addDevice();
      d.states
        ..add(state(d, _getTemp, false, 'setpoint', value: 21.0))
        ..add(state(d, _setTemp, true, 'setpoint'));
      final backend = answering([21.5]);
      final row = GlobalKey<_ListenerState>();
      final values = {for (final s in d.states) s: s.value};
      await pumpGolden(
          tester,
          Builder(
              builder: (context) => Scaffold(
                  body: _Listener(d, key: row, child: TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DetailPage(d, null))), child: const Text('open'))))),
          dark: false);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      values.forEach((s, v) {
        s.value = v;
        s.transitioning = false;
      });
      d.notifyStateChanged();
      await tester.pump();
      serveGoldenBackend(backend);

      await tester.runAsync(() async {
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add)).onPressed!();
      });
      final builds = row.currentState!.builds;
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(tester.takeException(), isNull);
      expect(row.currentState!.builds, greaterThan(builds), reason: 'the row of the list saw the change');
      expect(controlsSent(backend), hasLength(1));
      expect(controlsSent(backend).single['input'], 21.5);
    });

    testWidgets('picking the shown value of a dropdown again sends nothing', (tester) async {
      registerAll(modes: ['a', 'b', 'c', 'd', 'e']);
      final d = addDevice();
      d.states
        ..add(state(d, _getMode, false, 'mode', value: 'b'))
        ..add(state(d, _setMode, true, 'mode'));
      final backend = answering(['c']);
      await pump(tester, d, backend);

      final dropdown = tester.widget<DropdownButton<int>>(find.byType(DropdownButton<int>));
      expect(dropdown.value, 1);
      await tester.runAsync(() async {
        dropdown.onChanged!(1);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      expect(backend.requests, isEmpty);

      await tester.runAsync(() async {
        tester.widget<DropdownButton<int>>(find.byType(DropdownButton<int>)).onChanged!(2);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      expect(controlsSent(backend).single['input'], 'c');
    });

    testWidgets('a change that meets a busy row is dropped, not queued', (tester) async {
      registerAll();
      final d = addDevice();
      final reading = state(d, _getTemp, false, 'setpoint', value: 21.0);
      d.states
        ..add(reading)
        ..add(state(d, _setTemp, true, 'setpoint'));
      final backend = answering([22.0]);
      await pump(tester, d, backend);

      await tester.runAsync(() async {
        tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.add)).onPressed!();
        // Something else, such as a refresh, takes the row before the timer.
        reading.transitioning = true;
        await Future<void>.delayed(const Duration(milliseconds: 1000));
      });
      reading.transitioning = false;
      d.notifyStateChanged();
      await tester.pump();

      expect(backend.requests, isEmpty);
      expect(find.text('21 °C'), findsOneWidget, reason: 'the control shows the reading again');
    });

    testWidgets('allowed values are segments and send the chosen one', (tester) async {
      registerAll(modes: ['auto', 'heat', 'off']);
      final d = addDevice();
      d.states
        ..add(state(d, _getMode, false, 'mode', value: 'auto'))
        ..add(state(d, _setMode, true, 'mode'));
      final backend = answering(['heat']);
      await pump(tester, d, backend);

      final segments = tester.widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>));
      expect(segments.selected, {0});
      await tester.runAsync(() async {
        segments.onSelectionChanged!({1});
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(controlsSent(backend).single['input'], 'heat');
      expect(d.states.first.value, 'heat');
    });

    testWidgets('a structure keeps the dialog button', (tester) async {
      registerAll();
      final d = addDevice();
      d.states
        ..add(state(d, _getColor, false, 'colour', value: {'h': 10, 's': 50}))
        ..add(state(d, _setColor, true, 'colour'));
      await pump(tester, d, answering([1]));

      expect(find.byType(Slider), findsNothing);
      expect(find.descendant(of: find.byType(GroupedListTile), matching: find.byType(IconButton)), findsNothing);
      expect(find.descendant(of: find.byType(GroupedListTile), matching: find.byType(TextButton)), findsOneWidget);
    });

    testWidgets('the switch sends the opposite function and shows the value read back', (tester) async {
      registerAll();
      final d = addDevice();
      final reading = state(d, onOffFunction, false, 'output', value: true);
      d.states
        ..add(reading)
        ..add(state(d, setOnFunction, true, 'on'))
        ..add(state(d, setOffFunction, true, 'off'));
      final backend = answering([false]);
      await pump(tester, d, backend);

      final toggle = tester.widget<Switch>(find.byType(Switch));
      expect(toggle.value, isTrue);
      await tester.runAsync(() async {
        toggle.onChanged!(false);
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(sent(backend).map((c) => c['function_id']), [setOffFunction, onOffFunction]);
      expect(reading.value, isFalse);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
      expect(rowWith('Power'), findsOneWidget);
    });
  });
}

/// A stand-in for a device list row: it rebuilds whenever the device notifies.
class _Listener extends StatefulWidget {
  final DeviceInstance device;
  final Widget child;
  const _Listener(this.device, {required this.child, super.key});

  @override
  State<_Listener> createState() => _ListenerState();
}

class _ListenerState extends State<_Listener> {
  int builds = 0;

  void _changed() => setState(() {});

  @override
  void initState() {
    super.initState();
    widget.device.stateNotifier.addListener(_changed);
  }

  @override
  void dispose() {
    widget.device.stateNotifier.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    builds++;
    return widget.child;
  }
}
