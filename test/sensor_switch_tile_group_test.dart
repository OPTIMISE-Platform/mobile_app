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
import 'dart:async';

import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
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
  });

  // One testWidgets for every case, see sensor_switch_tile_device_test.dart.
  testWidgets('group switch tiles', (tester) async {
    final toasts = captureToasts();
    final backend = PlugBackend();
    backend.values['hall'] = [true, false];
    backend.values['mixed-classes'] = [true, true];
    backend.values['cellar'] = [false, false];
    // One plug of the porch does not answer.
    backend.values['porch'] = [true, null];
    // No value for 'attic': its read answers 502.
    backend.refusing.add('cellar');
    serveGoldenBackend(backend);
    await warmUpMgwStorage(tester);
    registerOnOffFunctions();
    AppState().deviceGroups.addAll([
      plugGroup('hall', ['class-plug']),
      plugGroup('mixed-classes', ['class-plug', 'class-lamp']),
      plugGroup('attic', ['class-plug']),
      plugGroup('cellar', ['class-plug']),
      plugGroup('porch', ['class-plug']),
    ]);

    final pins = [
      groupPin('hall', 'Hall'),
      groupPin('mixed-classes', 'Everything'),
      groupPin('attic', 'Attic'),
      groupPin('cellar', 'Cellar'),
      groupPin('porch', 'Porch'),
    ];
    await mountSensorPage(tester, pins);

    // An unreachable member does not keep the reachable one from going off.
    expect(labelOf(tester, 'Porch'), 'On');
    await tester.tap(inCard('Porch', find.byType(Switch)));
    await settle(tester);
    expect(backend.controls.where((c) => c['group_id'] == 'porch').map((c) => c['function_id']),
        [setOffFunction]);
    expect(labelOf(tester, 'Porch'), 'Off');
    expect(backend.values['porch'], [false, null]);

    // Members that disagree read as mixed, and a tap switches all of them on.
    expect(labelOf(tester, 'Hall'), 'Mixed');
    expect(switchOf(tester, 'Hall').value, isFalse);
    expect(switchOf(tester, 'Hall').thumbIcon, isNotNull,
        reason: 'neutral thumb for a mixed group');
    await tester.tap(inCard('Hall', find.byType(Switch)));
    await tester.tap(inCard('Hall', find.byType(Switch)));
    await settle(tester);
    expect(
        backend.commandsFor('hall').map((c) => [c['function_id'], c['device_class_id']]),
        [
          [onOffFunction, 'class-plug'],
          [setOnFunction, 'class-plug'],
          [onOffFunction, 'class-plug'],
        ],
        reason: 'the load, one control for two taps, one read-back');
    expect(labelOf(tester, 'Hall'), 'On');
    expect(switchOf(tester, 'Hall').value, isTrue);
    expect(toasts, isEmpty);

    // Two device classes bring two controls: no single command to send.
    expect(labelOf(tester, 'Everything'), 'On');
    expect(switchOf(tester, 'Everything').onChanged, isNull);
    expect(inkWellOf(tester, 'Everything').onTap, isNull);

    // An unknown group does not switch all its members on.
    expect(labelOf(tester, 'Attic'), 'Unknown');
    expect(switchOf(tester, 'Attic').onChanged, isNull);
    expect(inkWellOf(tester, 'Attic').onTap, isNull);
    await tester.tap(find.text('Everything'));
    await tester.tap(find.text('Attic'));
    await settle(tester);
    expect(backend.commandsFor('mixed-classes').where((c) => c['function_id'] != onOffFunction), isEmpty);
    expect(backend.commandsFor('attic').where((c) => c['function_id'] != onOffFunction), isEmpty);

    // A refused command toasts the message, like a device's.
    expect(labelOf(tester, 'Cellar'), 'Off');
    await tester.tap(find.text('Cellar'));
    await settle(tester);
    expect(toasts, ['Error running command: boom']);
    expect(backend.commandsFor('cellar').map((c) => c['function_id']),
        [onOffFunction, setOnFunction]);
    expect(labelOf(tester, 'Cellar'), 'Off');

    // A reload that read the shared group state before a command finished
    // does not flip the tile back when it lands afterwards.
    final heldLoad = Completer<void>();
    backend.holdLoads = heldLoad;
    AppState().pushRefresh();
    await settle(tester);
    expect(labelOf(tester, 'Hall'), 'On');
    await tester.tap(inCard('Hall', find.byType(Switch)));
    await settle(tester);
    expect(labelOf(tester, 'Hall'), 'Off');
    heldLoad.complete();
    backend.holdLoads = null;
    await settle(tester);
    expect(labelOf(tester, 'Hall'), 'Off',
        reason: 'the reload read "on" before the command switched it off');

    // A command another page runs on the shared group state keeps the tile
    // busy.
    final porch = AppState().deviceGroups.firstWhere((g) => g.id == 'porch');
    final porchReading = porch.states
        .firstWhere((s) => s.functionId == onOffFunction);
    porchReading.transitioning = true;
    porch.notifyStateChanged();
    await tester.pump();
    expect(switchOf(tester, 'Porch').onChanged, isNull);
    expect(inCard('Porch', find.byType(DelayedCircularProgressIndicator)),
        findsOneWidget);
    porchReading.transitioning = false;
    porch.notifyStateChanged();
    await tester.pump();

    // Leaving the page and coming back while a command runs: the remount's
    // load clears the group state's transitioning flag, yet the tile stays
    // busy and sends nothing more.
    final held = Completer<void>();
    backend.holdControls = held;
    await tester.tap(inCard('Porch', find.byType(Switch)));
    await tester.pump();
    await mountSensorPage(tester, pins);
    expect(porchReading.transitioning, isFalse);
    expect(switchOf(tester, 'Porch').onChanged, isNull);
    await tester.tap(find.text('Porch'));
    await settle(tester);
    held.complete();
    backend.holdControls = null;
    await settle(tester);
    expect(backend.controls.where((c) => c['group_id'] == 'porch').map((c) => c['function_id']),
        [setOffFunction, setOnFunction],
        reason: 'one command for the tap before leaving, none after');
    expect(labelOf(tester, 'Porch'), 'On');

    // In local mode a group outside a locally served network cannot be
    // switched.
    await tester.runAsync(() => Settings.setLocalMode(true));
    tester.view.physicalSize = const Size(412, 900);
    await settle(tester);
    expect(labelOf(tester, 'Porch'), 'Not local');
    expect(switchOf(tester, 'Porch').onChanged, isNull);
    expect(inkWellOf(tester, 'Porch').onTap, isNull);
    await tester.runAsync(() => Settings.setLocalMode(false));

    // Outlasts the toast plugin's own 2s timer.
    await tester.pump(const Duration(seconds: 3));
  });
}
