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
import 'package:mobile_app/widgets/shared/slice_position.dart';
import 'package:mobile_app/widgets/tabs/shared/device_list_item.dart';
import 'package:mobile_app/widgets/tabs/shared/group_list_item.dart';

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

  void registerAspects() {
    registerOnOffFunctions();
    for (final name in ['Device', 'Heating', 'Lighting']) {
      AppState().aspects[name.toLowerCase()] = Aspect(name.toLowerCase(), name, null);
    }
  }

  DeviceInstance switchDevice(String id, List<String> readingAspects, dynamic value) {
    final d = DeviceInstance(id, '$id-local', id, null, 'type-1', false, 'owner-1', id, DeviceConnectionStatus.online);
    DeviceState state(String function, bool controlling, dynamic v, List<String> aspects) =>
        DeviceState(v, 'svc', 'g-1', function, null, controlling, null, null, id, 'state', 'g-1', aspectIds: aspects)
          ..deviceInstance = d;
    d.states
      ..add(state(onOffFunction, false, value, readingAspects))
      ..add(state(setOnFunction, true, null, readingAspects))
      ..add(state(setOffFunction, true, null, readingAspects));
    return d;
  }

  DeviceGroup switchGroup(List<String> aspects, List<bool> values) {
    DeviceGroupCriteria criterion(String function) => DeviceGroupCriteria.fromJson({
          'aspect_id': aspects.first,
          'aspect_ids': aspects,
          'device_class_id': 'class-s',
          'function_id': function,
          'interaction': 'request',
        });
    final group = DeviceGroup('grp', 'Group', [
      criterion(onOffFunction),
      criterion(setOnFunction),
      criterion(setOffFunction),
    ], '', [], null)
      ..prepareStates();
    group.states.firstWhere((s) => s.functionId == onOffFunction).value = values;
    return group;
  }

  Finder rowButton(Type row) => find.descendant(of: find.byType(row), matching: find.byType(IconButton));

  Future<IconButton> pumpDevice(WidgetTester tester, DeviceInstance d) async {
    await pumpGolden(tester, Scaffold(body: DeviceListItem(d, null, position: SlicePosition.only)), dark: false);
    return tester.widget<IconButton>(rowButton(DeviceListItem));
  }

  Future<IconButton> pumpGroup(WidgetTester tester, DeviceGroup g) async {
    await pumpGolden(tester, Scaffold(body: GroupListItem(g, null, position: SlicePosition.only)), dark: false);
    return tester.widget<IconButton>(rowButton(GroupListItem));
  }

  IconData? iconOf(IconButton b) => (b.icon as Icon).icon;

  testWidgets('a device row toggle follows what the reading switches', (tester) async {
    await warmUpMgwStorage(tester);
    registerAspects();

    var b = await pumpDevice(tester, switchDevice('heater', ['heating'], true));
    expect(iconOf(b), Icons.local_fire_department);
    expect(b.tooltip, 'Heating on/off');

    b = await pumpDevice(tester, switchDevice('heater', ['heating'], false));
    expect(iconOf(b), Icons.local_fire_department_outlined);

    b = await pumpDevice(tester, switchDevice('lamp', ['device', 'lighting'], true));
    expect(iconOf(b), Icons.lightbulb);
    expect(b.tooltip, 'Light on/off');

    b = await pumpDevice(tester, switchDevice('lamp', ['device', 'lighting'], false));
    expect(iconOf(b), Icons.lightbulb_outline);

    b = await pumpDevice(tester, switchDevice('plug', ['device'], true));
    expect(iconOf(b), Icons.power_outlined);
    expect(b.tooltip, 'Switch off', reason: 'a plain switch keeps the control name');
  });

  testWidgets('a group row toggle follows what the reading switches', (tester) async {
    await warmUpMgwStorage(tester);
    registerAspects();

    var b = await pumpGroup(tester, switchGroup(['heating'], [true, true]));
    expect(iconOf(b), Icons.local_fire_department);
    expect(b.tooltip, 'Heating on/off');

    b = await pumpGroup(tester, switchGroup(['lighting'], [false, false]));
    expect(iconOf(b), Icons.lightbulb_outline);
    expect(b.tooltip, 'Light on/off');

    b = await pumpGroup(tester, switchGroup(['device'], [true, true]));
    expect(iconOf(b), Icons.power_outlined);
    expect(b.tooltip, 'Switch off');
  });
}
