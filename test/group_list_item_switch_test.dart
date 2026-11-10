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
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/widgets/shared/slice_position.dart';
import 'package:mobile_app/widgets/tabs/shared/group_list_item.dart';
import 'package:mobile_app/widgets/tabs/sensors/switch_commands.dart';

import 'golden_helper.dart';
import 'sensor_switch_fixture.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() async {
    resetAppStateForGolden();
    resetGoldenBackend();
    SwitchCommands.resetForTest();
    await Settings.setLocalMode(false);
  });

  DeviceState readingOf(DeviceGroup group) =>
      group.states.firstWhere((s) => s.functionId == onOffFunction);

  Finder rowSwitch() => find.descendant(
      of: find.byType(GroupListItem), matching: find.byType(IconButton));

  IconButton switchOfRow(WidgetTester tester) =>
      tester.widget<IconButton>(rowSwitch());

  testWidgets('a group row switches the group through its one control',
      (tester) async {
    final backend = PlugBackend();
    backend.values['hall'] = [true, true];
    serveGoldenBackend(backend);
    await warmUpMgwStorage(tester);
    registerOnOffFunctions();
    final group = plugGroup('hall', ['class-plug']);
    group.prepareStates();
    readingOf(group).value = [true, true];

    await pumpGolden(
      tester,
      Scaffold(
          body: GroupListItem(group, null, position: SlicePosition.only)),
      dark: false,
    );

    expect(rowSwitch(), findsOneWidget);
    expect(switchOfRow(tester).tooltip, 'Switch off',
        reason: 'the group is on, so the switch sends the off control');

    await tester.tap(rowSwitch());
    await settle(tester);

    expect(
        backend.controls
            .where((c) => c['group_id'] == 'hall')
            .map((c) => c['function_id']),
        [setOffFunction]);
    expect(switchOfRow(tester).tooltip, 'Switch on',
        reason: 'the value read back after the command');
  });

  testWidgets('a group with two controls for its reading has no row switch',
      (tester) async {
    registerOnOffFunctions();
    final group = plugGroup('mixed-classes', ['class-plug', 'class-lamp']);
    group.prepareStates();
    readingOf(group).value = [true, true];

    await pumpGolden(
      tester,
      Scaffold(
          body: GroupListItem(group, null, position: SlicePosition.only)),
      dark: false,
    );

    expect(rowSwitch(), findsNothing,
        reason: 'no single command goes with the group');
  });

  testWidgets('a group outside a local network shows why and has no switch',
      (tester) async {
    registerOnOffFunctions();
    final group = plugGroup('hall', ['class-plug']);
    group.prepareStates();
    readingOf(group).value = [true, true];

    await tester.runAsync(() => Settings.setLocalMode(true));
    await pumpGolden(
      tester,
      Scaffold(
          body: GroupListItem(group, null, position: SlicePosition.only)),
      dark: false,
    );

    expect(find.text('Not local'), findsOneWidget);
    expect(rowSwitch(), findsNothing);
  });

  testWidgets('a group whose reading is unknown shows the status icon, not a switch',
      (tester) async {
    registerOnOffFunctions();
    final group = plugGroup('hall', ['class-plug']);
    group.prepareStates();
    readingOf(group).value = [null, null];

    await pumpGolden(
      tester,
      Scaffold(
          body: GroupListItem(group, null, position: SlicePosition.only)),
      dark: false,
    );

    expect(find.byTooltip('Status unknown'), findsOneWidget);
    expect(rowSwitch(), findsNothing);
  });
}
