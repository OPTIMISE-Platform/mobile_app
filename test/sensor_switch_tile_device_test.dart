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
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/tabs/sensors/switch_commands.dart';

import 'fake_backend.dart';
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

  // One testWidgets for every case: Dio instances are memoized for the
  // process, and a second test's requests may never be answered
  // (docs/testing.md).
  testWidgets('device switch tiles', (tester) async {
    final toasts = captureToasts();
    final backend = PlugBackend();
    backend.serveJson('GET', devicesPath, 200, [
      deviceJson('fan', 'Bathroom fan', deviceTypeId: 'plug'),
      deviceJson('pump', 'Garden pump', deviceTypeId: 'plug'),
      deviceJson('heater', 'Heater',
          deviceTypeId: 'plug', connectionState: 'offline'),
      deviceJson('lamp', 'Desk lamp', deviceTypeId: 'plug'),
      deviceJson('meter', 'Power meter', deviceTypeId: 'reader'),
    ]);
    backend.serveJson('POST', '/db/v3/queries', 200, [[]]);
    backend.values['fan'] = true;
    backend.values['lamp'] = true;
    backend.values['heater'] = true;
    backend.values['meter'] = true;
    // No value for the pump: its read answers 502.
    backend.refusing.add('lamp');
    serveGoldenBackend(backend);
    await warmUpMgwStorage(tester);
    AppState().deviceTypes['plug'] = plugType('plug');
    AppState().deviceTypes['reader'] = readerType('reader');
    registerOnOffFunctions();

    final pins = [
      plugPin('fan', 'Fan'),
      plugPin('pump', 'Pump'),
      plugPin('heater', 'Heater power'),
      plugPin('lamp', 'Lamp'),
      plugPin('meter', 'Meter'),
    ];
    await mountSensorPage(tester, pins);

    // TalkBack reads one node per tile: title, state and the toggle.
    final semantics = tester.ensureSemantics();
    expect(tester.getSemantics(inCard('Fan', find.byType(Switch))).id,
        tester.getSemantics(find.text('Fan')).id,
        reason: 'the switch is part of the card, not a node of its own');
    expect(
        tester.getSemantics(find.text('Fan')),
        matchesSemantics(
          label: 'Bathroom fan\nFan\nOn',
          hasToggledState: true,
          isToggled: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
          hasLongPressAction: true,
        ));
    semantics.dispose();

    // A reading without exactly one control is passive and toasts nothing.
    expect(labelOf(tester, 'Meter'), 'On');
    expect(switchOf(tester, 'Meter').onChanged, isNull);
    await tester.tap(find.text('Meter'));
    await settle(tester);
    expect(backend.commandsFor('meter').map((c) => c['function_id']),
        [onOffFunction]);

    expect(labelOf(tester, 'Fan'), 'On');
    expect(switchOf(tester, 'Fan').value, isTrue);
    expect(switchOf(tester, 'Fan').onChanged, isNotNull);

    // No history query for an on/off reading.
    expect(
        backend.requests.where((r) => r.uri.path == '/db/v3/queries'), isEmpty,
        reason: 'an on/off reading draws no sparkline');

    // An unknown state does not switch.
    expect(labelOf(tester, 'Pump'), 'Unknown');
    expect(switchOf(tester, 'Pump').onChanged, isNull);
    expect(inkWellOf(tester, 'Pump').onTap, isNull,
        reason: 'tapping an unknown state must not switch the device on');
    await tester.tap(find.text('Pump'));
    await settle(tester);
    expect(backend.controls, isEmpty);

    // An offline device's switch is disabled and shows why.
    expect(labelOf(tester, 'Heater power'), 'Offline');
    expect(inCard('Heater power', find.byIcon(Icons.error)), findsOneWidget);
    expect(switchOf(tester, 'Heater power').onChanged, isNull);
    expect(inkWellOf(tester, 'Heater power').onTap, isNull);

    // Tapping switches through the control, once, and reads the value back.
    await tester.tap(inCard('Fan', find.byType(Switch)));
    await tester.tap(inCard('Fan', find.byType(Switch)));
    await settle(tester);
    expect(backend.commandsFor('fan').map((c) => c['function_id']),
        [onOffFunction, setOffFunction, onOffFunction],
        reason: 'the load, one control for two taps, one read-back');
    expect(labelOf(tester, 'Fan'), 'Off');
    expect(switchOf(tester, 'Fan').value, isFalse);
    expect(toasts, isEmpty);

    // Tapping the card works the same.
    await tester.tap(find.text('Fan'));
    await settle(tester);
    expect(backend.controls.map((c) => c['function_id']),
        [setOffFunction, setOnFunction]);
    expect(labelOf(tester, 'Fan'), 'On');

    // A refused command toasts the backend's message and reads nothing back.
    await tester.tap(inCard('Lamp', find.byType(Switch)));
    await settle(tester);
    expect(toasts, ['Error running command: boom']);
    expect(backend.commandsFor('lamp').map((c) => c['function_id']),
        [onOffFunction, setOffFunction]);
    expect(labelOf(tester, 'Lamp'), 'On');
    expect(switchOf(tester, 'Lamp').onChanged, isNotNull,
        reason: 'the spinner is gone and the tile can be tapped again');

    // A reload while a command runs puts new states on the card; the tile
    // stays busy, sends nothing more and shows the value read back after.
    final hold = Completer<void>();
    backend.holdControls = hold;
    await tester.tap(inCard('Fan', find.byType(Switch)));
    await tester.pump();
    AppState().pushRefresh();
    await settle(tester);
    expect(switchOf(tester, 'Fan').onChanged, isNull);
    await tester.tap(find.text('Fan'));
    await settle(tester);
    expect(backend.controls.where((c) => c['device_id'] == 'fan'), hasLength(3),
        reason: 'one command for the tap before the reload, none after');
    expect(labelOf(tester, 'Fan'), 'On', reason: 'read before the command ran');
    hold.complete();
    backend.holdControls = null;
    await settle(tester);
    expect(labelOf(tester, 'Fan'), 'Off');
    expect(switchOf(tester, 'Fan').onChanged, isNotNull);

    // A reload whose values were read before the command finished does not
    // flip the tile back when it lands afterwards.
    final heldLoad = Completer<void>();
    backend.holdLoads = heldLoad;
    AppState().pushRefresh();
    await settle(tester);
    await tester.tap(inCard('Fan', find.byType(Switch)));
    await settle(tester);
    expect(labelOf(tester, 'Fan'), 'On');
    heldLoad.complete();
    backend.holdLoads = null;
    await settle(tester);
    expect(labelOf(tester, 'Fan'), 'On',
        reason: 'the reload read "off" before the command switched it on');

    // Leaving the page and coming back while a command runs: the new page
    // shows it running and sends nothing more.
    final heldRemount = Completer<void>();
    backend.holdControls = heldRemount;
    await tester.tap(inCard('Fan', find.byType(Switch)));
    await tester.pump();
    await mountSensorPage(tester, pins);
    expect(switchOf(tester, 'Fan').onChanged, isNull);
    expect(inCard('Fan', find.byType(DelayedCircularProgressIndicator)),
        findsOneWidget);
    await tester.tap(find.text('Fan'));
    await settle(tester);
    heldRemount.complete();
    backend.holdControls = null;
    await settle(tester);
    expect(backend.controls.where((c) => c['device_id'] == 'fan'), hasLength(5),
        reason: 'one command for the tap before leaving, none after');
    expect(labelOf(tester, 'Fan'), 'Off');
    expect(switchOf(tester, 'Fan').onChanged, isNotNull);

    // Local mode without a gateway makes the device unavailable, even with
    // the value it last read.
    await tester.runAsync(() => Settings.setLocalMode(true));
    // A new surface size rebuilds the grid without reloading it.
    tester.view.physicalSize = const Size(412, 900);
    await settle(tester);
    expect(labelOf(tester, 'Fan'), 'Not local');
    expect(inCard('Fan', find.byIcon(Icons.lan_outlined)), findsOneWidget);
    expect(switchOf(tester, 'Fan').onChanged, isNull);
    expect(inkWellOf(tester, 'Fan').onTap, isNull);
    await tester.runAsync(() => Settings.setLocalMode(false));
  });
}
