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
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/detail_page.dart';

import 'golden_helper.dart';
import 'sensor_switch_fixture.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(resetAppStateForGolden);

  Finder rowOf(String title) =>
      find.ancestor(of: find.text(title), matching: find.byType(ListTile));

  IconButton buttonOf(WidgetTester tester, String title) => tester.widget(
      find.descendant(of: rowOf(title), matching: find.byType(IconButton)));

  testWidgets('an unknown on/off state leaves its controls to their own rows',
      (tester) async {
    registerOnOffFunctions();
    AppState().deviceTypes['plug'] = plugType('plug');
    final d = DeviceInstance('fan', 'fan-local', 'Bathroom fan', null, 'plug',
        false, 'owner-1', 'Bathroom fan', DeviceConnectionStatus.online);
    DeviceState state(String functionId, bool controlling) => DeviceState(
        null, 'svc', 'group-1', functionId, null, controlling, null, null,
        d.id, 'on', null,
        aspectIds: const ['power'])
      ..deviceInstance = d;
    final reading = state(onOffFunction, false);
    d.states
      ..add(reading)
      ..add(state(setOnFunction, true))
      ..add(state(setOffFunction, true));
    AppState().devices.add(d);

    await pumpGolden(tester, DetailPage(d, null), dark: false);
    // After the page's own value load, which fails without a backend.
    reading.value = null;
    d.notifyStateChanged();
    await tester.pump();

    expect(find.descendant(of: rowOf('Power'), matching: find.byType(IconButton)),
        findsNothing,
        reason: 'the config would pick "switch on" for an unknown state');
    expect(find.descendant(of: rowOf('Power'), matching: find.byType(TextButton)),
        findsNothing);
    expect(buttonOf(tester, 'Switch on').onPressed, isNotNull);
    expect(buttonOf(tester, 'Switch off').onPressed, isNotNull);

    // A known state folds the controls into the reading's row again.
    reading.value = true;
    d.notifyStateChanged();
    await tester.pump();
    expect(buttonOf(tester, 'Power').onPressed, isNotNull);
    expect(find.text('Switch on'), findsNothing);
    expect(find.text('Switch off'), findsNothing);
  });

  testWidgets('a group whose members all did not answer keeps its controls',
      (tester) async {
    registerOnOffFunctions();
    // The page waits until the members are among the loaded devices; group
    // member ids are at least 57 characters long.
    final memberId = 'urn:infai:ses:device:${'0' * 36}';
    AppState().devices.add(DeviceInstance(memberId, 'plug-local', 'Plug', null,
        'plug', false, 'owner-1', 'Plug', DeviceConnectionStatus.online));
    final group = plugGroup('hall', ['class-plug'])..device_ids = [memberId];
    AppState().deviceGroups.add(group);
    group.prepareStates();

    await pumpGolden(tester, DetailPage(null, group), dark: false);
    final reading =
        group.states.firstWhere((s) => s.functionId == onOffFunction);
    reading.value = [null, null];
    group.notifyStateChanged();
    await tester.pump();

    expect(find.descendant(of: rowOf('Power'), matching: find.byType(IconButton)),
        findsNothing);
    expect(buttonOf(tester, 'Switch on').onPressed, isNotNull);
    expect(buttonOf(tester, 'Switch off').onPressed, isNotNull);
  });

  testWidgets('a lamp group lists its on/off state once, on the combination',
      (tester) async {
    registerOnOffFunctions();
    for (final id in ['device', 'lighting']) {
      AppState().aspects[id] = Aspect(id, id, null);
    }
    // device-repository adds the subsets of [device, lighting] as criteria
    // of their own, for the reading and both controls.
    DeviceGroupCriteria criterion(String functionId, List<String> aspectIds) =>
        DeviceGroupCriteria.fromJson({
          'aspect_id': aspectIds.first,
          'aspect_ids': aspectIds,
          'device_class_id': '',
          'function_id': functionId,
          'interaction': 'request',
        });
    final memberId = 'urn:infai:ses:device:${'0' * 36}';
    AppState().devices.add(DeviceInstance(memberId, 'lamp-local', 'Lamp', null,
        'lamp', false, 'owner-1', 'Lamp', DeviceConnectionStatus.online));
    final group = DeviceGroup('lamps', 'Living room lamps', [
      for (final f in [onOffFunction, setOnFunction, setOffFunction])
        for (final aspects in [
          ['device', 'lighting'],
          ['device'],
          ['lighting'],
        ])
          criterion(f, aspects),
    ], '', [memberId], null);
    AppState().deviceGroups.add(group);
    group.prepareStates();

    await pumpGolden(tester, DetailPage(null, group), dark: false);
    final reading = group.states.firstWhere((s) =>
        s.functionId == onOffFunction && s.aspectIds.length == 2);
    reading.value = [true];
    group.notifyStateChanged();
    await tester.pump();

    expect(find.text('Power'), findsOneWidget);
    expect(find.text('Switch on'), findsNothing);
    expect(find.text('Switch off'), findsNothing);
  });
}
