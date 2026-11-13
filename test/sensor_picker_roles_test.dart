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
import 'package:mobile_app/models/aspect.dart';
import 'package:mobile_app/models/content.dart';
import 'package:mobile_app/models/content_variable.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/models/service.dart';
import 'package:mobile_app/widgets/tabs/sensors/sensor_picker.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';
import 'thermostat_fixture.dart';

/// The same for every test: the device page is cached by its address.
final _devices = [
  deviceJson('trv', 'Radiator', deviceTypeId: 'dt-trvzb'),
  deviceJson('heater', 'Heater', deviceTypeId: 'dt-heater'),
];

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  Future<void> pump(WidgetTester tester, [int times = 5]) async {
    for (var i = 0; i < times; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// The value rows as (title, subtitle), top to bottom.
  List<(String, String?)> rows(WidgetTester tester) => [
        for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
          if (tile.trailing is Row)
            ((tile.title! as Text).data!, (tile.subtitle as Text?)?.data),
      ];

  Future<void> openPicker(WidgetTester tester, List<Map<String, dynamic>> devices) async {
    await warmUpMgwStorage(tester);
    final backend = FakeBackend();
    backend.serveJson('GET', '/device-repository/device-groups', 200, []);
    backend.serveJson('GET', '/device-repository/extended-hubs', 200, []);
    backend.serveJson('GET', '/device-repository/device-types', 200, []);
    backend.serveJson('GET', '/device-repository/user-device-types', 200, []);
    backend.serveDevicesPaged(devices);
    serveGoldenBackend(backend);
    late BuildContext capturedContext;
    await pumpGolden(
      tester,
      Builder(builder: (context) {
        capturedContext = context;
        return const SizedBox();
      }),
      dark: false,
    );
    unawaited(pickSensors(capturedContext));
    await pump(tester, 20);
    // After the picker's own metadata load, which replaces what it cannot fetch.
    registerThermostatMetadata();
  }

  testWidgets('a thermostat lists its readings, then its external input; controls of the same title get their aspects',
      (tester) async {
    await openPicker(tester, _devices);
    AppState().deviceTypes['dt-trvzb'] = trvzbType('dt-trvzb');

    await tester.tap(find.text('Radiator'));
    await pump(tester);

    expect(rows(tester), [
      ('Target Temperature', null),
      ('Temperature', null),
      ('External temperature input', 'Feeds a measured value to the device'),
    ]);
    expect(find.text('Set-Temperature'), findsNothing);
    expect(find.textContaining('Air, Indoor'), findsNothing, reason: 'no title needs the aspect list');

    // Dio instances are memoized for the process (docs/testing.md), so a
    // later test of this file would not load the device list again.
    Navigator.of(tester.element(find.text('External temperature input'))).pop();
    await pump(tester, 20);
    AppState().aspects['outdoor'] = Aspect('outdoor', 'Outdoor', null);
    AppState().aspects['water'] = Aspect('water', 'Water', null);
    ContentVariable variable(String name, String functionId, List<String> aspects) => ContentVariable('cv-$name', name,
        celsius, null, aspects.first, functionId, 'https://schema.org/Float', null, null, null, aspects);
    Service service(String name, ContentVariable v, {required bool input}) => Service('svc-$name', 'local-$name', name,
        '', 'protocol-1', 'request', 'group-h', input ? [Content('c-$name', 'json', 's', v)] : null,
        input ? null : [Content('c-$name', 'json', 's', v)]);
    // Two controls that pair with no reading.
    AppState().deviceTypes['dt-heater'] = DeviceType('dt-heater', 'Heater', '', 'class-heater', [
      service('get', variable('room', getTemperature, const ['air', 'indoor']), input: false),
      service('set_outdoor', variable('outdoor', setTemperature, const ['air', 'outdoor']), input: true),
      service('set_water', variable('water', setTemperature, const ['water']), input: true),
    ], null);

    await tester.tap(find.text('Heater'));
    await pump(tester, 20);

    final heater = rows(tester);
    expect(heater.first, ('Temperature', null), reason: 'a control is not named like its reading');
    expect(heater.skip(1), unorderedEquals([('Set temperature', 'Air, Outdoor'), ('Set temperature', 'Water')]),
        reason: 'only controls of the same title get their aspects');

    await pump(tester, 10);
  });

  testWidgets('a group of thermostats lists the same rows', (tester) async {
    await openPicker(tester, _devices);
    AppState().deviceGroups.add(DeviceGroup('trvs', 'Radiators', trvzbGroupCriteria(), '', [], null));

    await tester.tap(find.text('Groups'));
    await pump(tester);
    await tester.tap(find.text('Radiators'));
    await pump(tester);

    expect(rows(tester), [
      ('Target Temperature', null),
      ('Temperature', null),
      ('External temperature input', 'Feeds a measured value to the device'),
    ]);

    await pump(tester, 10);
  });
}
