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

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/models/sensor_pin.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/inline_control.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';
import 'sensor_switch_fixture.dart';
import 'thermostat_fixture.dart';

/// Answers the command batch like thermostats: a read of a temperature with
/// the role Target returns [setpoints], any other [measured], for the device
/// or group (a group's as the list of its members); a set of the setpoint
/// stores its input.
class _ThermostatBackend extends FakeBackend {
  final Map<String, dynamic> setpoints = {}, measured = {};
  final List<Map<String, dynamic>> commands = [];

  List<Map<String, dynamic>> get sets => commands.where((c) => c['function_id'] == setTemperature).toList();

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (options.uri.path != batchPath) return super.fetch(options, requestStream, cancelFuture);
    requests.add(options);
    final batch = (jsonDecode(options.data as String) as List).cast<Map<String, dynamic>>();
    commands.addAll(batch);
    final answers = [
      for (final c in batch)
        () {
          final id = (c['device_id'] ?? c['group_id']) as String;
          final target = (c['aspect_ids'] as List?)?.contains('target') ?? false;
          final values = target ? setpoints : measured;
          if (c['function_id'] == setTemperature) {
            if (!target) return {'status_code': 500, 'message': 'not a setpoint'};
            final current = values[id];
            values[id] = current is List ? [for (final _ in current) c['input']] : c['input'];
            return {'status_code': 200, 'message': null};
          }
          final value = values[id];
          return {'status_code': 200, 'message': value is List ? value : [value]};
        }(),
    ];
    return ResponseBody.fromString(jsonEncode(answers), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }
}

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  SensorPin devicePin(String functionId, List<String> aspects, String alias, {bool controlling = false}) => SensorPin(
      deviceId: 'trv',
      functionId: functionId,
      aspectId: ([...aspects]..sort()).first,
      aspectIds: [...aspects]..sort(),
      serviceGroupKey: 'group-t',
      isControlling: controlling,
      alias: alias);

  /// The stepper's text in the card titled [alias].
  Text stepperText(WidgetTester tester, String alias) =>
      tester.widget<Text>(inCard(alias, find.byKey(const Key('stepperValue'))));

  String shown(WidgetTester tester, String alias) => stepperText(tester, alias).textSpan!.toPlainText();

  bool pending(WidgetTester tester, String alias) =>
      (stepperText(tester, alias).textSpan! as TextSpan).children!.last.style?.fontStyle == FontStyle.italic;

  IconButton button(WidgetTester tester, String alias, String tooltip) =>
      tester.widget<IconButton>(inCard(alias, find.widgetWithIcon(IconButton, tooltip == 'Increase' ? Icons.add : Icons.remove)));

  Future<void> tapStep(WidgetTester tester, String alias, String tooltip) async {
    await tester.tap(inCard(alias, find.byTooltip(tooltip)));
    await tester.pump(const Duration(milliseconds: 100));
  }

  // One testWidgets: Dio instances are memoized for the process (docs/testing.md).
  testWidgets('a thermostat\'s cards set the setpoint with minus and plus', (tester) async {
    final toasts = captureToasts();
    final backend = _ThermostatBackend();
    backend.serveJson('GET', devicesPath, 200, [deviceJson('trv', 'Radiator', deviceTypeId: 'dt-trvzb')]);
    backend.serveJson('POST', '/db/v3/queries', 200, [[]]);
    backend.setpoints['trv'] = 29.0;
    backend.measured['trv'] = 19.5;
    backend.setpoints['trvs'] = [20.0];
    backend.measured['trvs'] = [18.0];
    serveGoldenBackend(backend);
    await warmUpMgwStorage(tester);
    registerThermostatMetadata();
    AppState().deviceTypes['dt-trvzb'] = trvzbType('dt-trvzb');
    final group = DeviceGroup('trvs', 'Radiators', trvzbGroupCriteria(), '', [], null)..prepareStates();
    AppState().deviceGroups.add(group);
    DeviceState groupReading(List<String> aspects) =>
        group.states.singleWhere((s) => !s.isControlling && s.aspectKey == ([...aspects]..sort()).join(','));

    await mountSensorPage(tester, [
      devicePin(getTemperature, setpointAspects, 'Setpoint'),
      devicePin(getTemperature, readingAspects, 'Room'),
      // Written when the picker still listed the setpoint control.
      devicePin(setTemperature, setpointAspects, 'Old pin', controlling: true),
      SensorPin.of(groupReading(readingAspects)).copyWith(alias: 'Radiators'),
      // A pin from before aspect lists names only one aspect.
      SensorPin.of(groupReading(const ['air'])).copyWith(alias: 'Air of radiators'),
    ]);

    // The setpoint's own card: steps of 0.5 up to the 30 °C a thermostat takes.
    expect(shown(tester, 'Setpoint'), '29 °C');
    await tapStep(tester, 'Setpoint', 'Increase');
    await tapStep(tester, 'Setpoint', 'Increase');
    expect(button(tester, 'Setpoint', 'Increase').onPressed, isNull, reason: 'at the maximum');
    await tapStep(tester, 'Setpoint', 'Increase');
    expect(shown(tester, 'Setpoint'), '30 °C');
    expect(pending(tester, 'Setpoint'), isTrue, reason: 'chosen, not read back');
    expect(backend.sets, isEmpty, reason: 'taps within the window are collected');

    await tester.pump(inlineControlDebounce);
    await settle(tester);

    expect(backend.sets.map((c) => c['input']), [30.0], reason: 'one command with the final value');
    expect(backend.sets.single['aspect_ids'], ([...setpointAspects]..sort()));
    expect(shown(tester, 'Setpoint'), '30 °C');
    expect(pending(tester, 'Setpoint'), isFalse);

    // The measured value's card: its own value without a control, the setpoint below.
    expect(find.descendant(of: cardOf('Room'), matching: find.text('19.5 °C')), findsOneWidget);
    expect(shown(tester, 'Room'), 'Target 30 °C');
    expect(find.descendant(of: cardOf('Room'), matching: find.byType(IconButton)), findsNWidgets(2),
        reason: 'minus and plus only: the external input is no setting of the room temperature');
    await tapStep(tester, 'Room', 'Decrease');
    await tapStep(tester, 'Room', 'Decrease');
    expect(shown(tester, 'Room'), 'Target 29 °C');
    await tester.pump(inlineControlDebounce);
    await settle(tester);
    expect(backend.sets.map((c) => c['input']), [30.0, 29.0]);
    expect(shown(tester, 'Setpoint'), '29 °C', reason: 'both cards show the setpoint read back');

    // A pin on the setpoint control still opens its input.
    final oldPin = inCard('Old pin', find.byType(IconButton));
    expect(tester.widget<IconButton>(oldPin).onPressed, isNotNull);
    await tester.tap(oldPin);
    await settle(tester);
    expect(find.text('Configure'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settle(tester);

    // A group's measured value gets the setpoint of the group.
    expect(shown(tester, 'Radiators'), 'Target 20 °C');
    await tapStep(tester, 'Radiators', 'Increase');
    await tester.pump(inlineControlDebounce);
    await settle(tester);
    expect(backend.sets.last['group_id'], 'trvs');
    expect(backend.sets.last['input'], 20.5);
    expect(shown(tester, 'Radiators'), 'Target 20.5 °C');

    // A group value on a part of the aspects sets nothing: its control would
    // reach the setpoint and the external input of every member alike.
    expect(find.descendant(of: cardOf('Air of radiators'), matching: find.byType(IconButton)), findsNothing);
    final sentBefore = backend.sets.length;
    await tester.tap(cardOf('Air of radiators'));
    await settle(tester);
    expect(find.text('Configure'), findsNothing);
    expect(backend.sets, hasLength(sentBefore));

    expect(toasts, isEmpty);

    // The cards keep to their size at a large text scale.
    await mountSensorPage(tester, [
      devicePin(getTemperature, setpointAspects, 'Setpoint'),
      devicePin(getTemperature, readingAspects, 'Room'),
    ], textScale: 2.0);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1));
  });
}
