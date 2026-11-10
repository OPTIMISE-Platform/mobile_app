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
import 'package:mobile_app/models/content.dart';
import 'package:mobile_app/models/content_variable.dart';
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/models/sensor_pin.dart';
import 'package:mobile_app/models/service.dart';
import 'package:mobile_app/widgets/tabs/sensors/switch_commands.dart';
import 'package:mobile_app/widgets/tabs/sensors/switch_tile.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';
import 'sensor_switch_fixture.dart';

ContentVariable _variable(String name, String functionId, List<String> aspects, {String? characteristicId}) =>
    ContentVariable('cv-$name', name, characteristicId, null, aspects.first, functionId, 'https://schema.org/String',
        null, null, null, aspects);

Service _service(String key, ContentVariable variable, {bool controlling = false}) =>
    Service('svc-${variable.name}', 'local-${variable.name}', variable.name!, '', 'protocol-1', 'request', key,
        controlling ? [Content('c-${variable.name}', 'json', 'segment-1', variable)] : null,
        controlling ? null : [Content('c-${variable.name}', 'json', 'segment-1', variable)]);

/// Bosch-like thermostat: running state (idle/heat) and system mode (off/heat).
DeviceType _thermostat() => DeviceType('thermostat', 'Thermostat', '', 'class-t', [
      _service('g-run', _variable('running_state', onOffFunction, ['heating'])),
      _service('g-mode', _variable('system_mode', onOffFunction, ['device', 'heating'], characteristicId: 'char-off-heat')),
    ], null);

DeviceType _button() => DeviceType('button', 'Button', '', 'class-b', [
      _service('g-in', _variable('state', onOffFunction, ['button'])),
    ], null);

/// A reading with its two controls, on [aspects] for the control.
DeviceType _switchable(String id, List<String> readingAspects, List<String> controlAspects) =>
    DeviceType(id, id, '', 'class-s', [
      _service('g-1', _variable('state', onOffFunction, readingAspects)),
      _service('g-1', _variable('on', setOnFunction, controlAspects), controlling: true),
      _service('g-1', _variable('off', setOffFunction, controlAspects), controlling: true),
    ], null);

SensorPin _pin(String deviceId, String group, List<String> aspects) => SensorPin(
    deviceId: deviceId, functionId: onOffFunction, aspectId: aspects.first, aspectIds: aspects, serviceGroupKey: group);

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
    resetGoldenBackend();
    SwitchCommands.resetForTest();
  });

  List<String> textsOf(WidgetTester tester, int card) => [
        for (final t in tester.widgetList<Text>(find.descendant(of: find.byType(Card).at(card), matching: find.byType(Text))))
          t.data ?? ''
      ];

  // One testWidgets: Dio instances are memoized for the process (docs/testing.md).
  testWidgets('sensor cards title and word on/off readings by role', (tester) async {
    final backend = PlugBackend();
    backend.serveJson('GET', devicesPath, 200, [
      deviceJson('heating', 'Heating device', deviceTypeId: 'thermostat'),
      deviceJson('idle', 'Idle device', deviceTypeId: 'thermostat'),
      deviceJson('button', 'Wall button', deviceTypeId: 'button'),
      deviceJson('plug', 'Fan', deviceTypeId: 'plug'),
      deviceJson('lamp', 'Lamp', deviceTypeId: 'lamp'),
    ]);
    backend.serveJson('POST', '/db/v3/queries', 200, [[]]);
    backend.values['heating'] = 'heat';
    backend.values['idle'] = 'idle';
    backend.values['button'] = true;
    backend.values['plug'] = true;
    backend.values['lamp'] = false;
    serveGoldenBackend(backend);
    await warmUpMgwStorage(tester);
    AppState().deviceTypes['thermostat'] = _thermostat();
    AppState().deviceTypes['button'] = _button();
    AppState().deviceTypes['plug'] = _switchable('plug', ['device'], ['device']);
    AppState().deviceTypes['lamp'] = _switchable('lamp', ['device', 'lighting'], ['lighting']);
    AppState().characteristics['char-off-heat'] = Characteristic(
        'char-off-heat', 'Binary State (off/heat)', ContentVariable.string, null, null, null, null, '', ['off', 'heat']);
    for (final name in ['Device', 'Button', 'Heating', 'Lighting']) {
      AppState().aspects[name.toLowerCase()] = Aspect(name.toLowerCase(), name, null);
    }
    registerOnOffFunctions();
    AppState().platformFunctions[onOffFunction]!
      ..display_name = 'Get-Binary State'
      ..name = 'Get-Binary State';

    await mountSensorPage(tester, [
      _pin('heating', 'g-run', ['heating']),
      _pin('heating', 'g-mode', ['device', 'heating']),
      _pin('idle', 'g-run', ['heating']),
      _pin('button', 'g-in', ['button']),
      _pin('plug', 'g-1', ['device']),
      _pin('lamp', 'g-1', ['device', 'lighting']),
    ]);

    // A reading nothing switches shows its state as text, never a power icon.
    expect(textsOf(tester, 0), containsAll(['Heating', 'Heating']));
    expect(textsOf(tester, 0).where((t) => t == 'Heating'), hasLength(2), reason: 'role title and value');
    expect(textsOf(tester, 1), containsAll(['Heating enabled', 'On']));
    expect(textsOf(tester, 2), containsAll(['Heating', 'Idle']));
    expect(textsOf(tester, 3), containsAll(['Button input', 'On']));
    for (var i = 0; i < 4; i++) {
      expect(find.descendant(of: find.byType(Card).at(i), matching: find.byType(Icon)), findsNothing, reason: 'card $i');
      expect(find.descendant(of: find.byType(Card).at(i), matching: find.byType(Switch)), findsNothing, reason: 'card $i');
    }

    // A switch keeps its tile and is titled by its role.
    expect(textsOf(tester, 4), containsAll(['Power', 'On']));
    expect(find.descendant(of: find.byType(Card).at(4), matching: find.byType(SwitchTileFooter)), findsOneWidget);
    expect(textsOf(tester, 5), containsAll(['Power', 'Off']));
    expect(find.descendant(of: find.byType(Card).at(5), matching: find.byType(SwitchTileFooter)), findsOneWidget);
  });
}
