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
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/detail_page.dart';

import 'golden_helper.dart';
import 'sensor_switch_fixture.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() async {
    resetAppStateForGolden();
    await Settings.setLocalMode(false);
  });

  Finder rowOf(String title) =>
      find.ancestor(of: find.text(title), matching: find.byType(ListTile));

  IconButton buttonOf(WidgetTester tester, String title) => tester.widget(
      find.descendant(of: rowOf(title), matching: find.byType(IconButton)));

  /// The lan icon in the page header. The app bar shows one too in local mode.
  Finder headerLanIcon() => find.descendant(
      of: find.byType(ListTile).first,
      matching: find.byIcon(Icons.lan_outlined));

  /// A network that holds [localIds] and, when [gateway], a local gateway.
  Network networkWith(List<String> localIds, {required bool gateway}) =>
      Network('network-1', 'Home', false, localIds, [],
          DeviceConnectionStatus.online, '', 'owner-1')
        ..localGateways = gateway
            ? [MGW('gw.local', 'gw', '', '10.0.0.2', networkId: 'network-1')]
            : null;

  testWidgets(
      'local mode without a gateway locks a device page\'s controls and shows why',
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
    AppState().networks.add(networkWith(['fan-local'], gateway: false));

    await tester.runAsync(() => Settings.setLocalMode(true));
    await pumpGolden(tester, DetailPage(d, null), dark: false);
    // After the page's own value load, which fails without a backend.
    reading.value = true;
    d.notifyStateChanged();
    await tester.pump();

    expect(buttonOf(tester, 'Power').onPressed, isNull,
        reason: 'the reading switches through a control no gateway serves');
    expect(headerLanIcon(), findsOneWidget,
        reason: 'the header says why');

    // A gateway on the network makes the controls available again.
    AppState().networks.single.localGateways = [
      MGW('gw.local', 'gw', '', '10.0.0.2', networkId: 'network-1'),
    ];
    d.notifyStateChanged();
    await tester.pump();

    expect(buttonOf(tester, 'Power').onPressed, isNotNull);
  });

  testWidgets(
      'local mode without a local network locks a group page\'s controls',
      (tester) async {
    registerOnOffFunctions();
    // The page waits until the members are among the loaded devices; group
    // member ids are at least 57 characters long.
    final memberId = 'urn:infai:ses:device:${'0' * 36}';
    AppState().devices.add(DeviceInstance(memberId, 'plug-local', 'Plug', null,
        'plug', false, 'owner-1', 'Plug', DeviceConnectionStatus.online));
    final group = plugGroup('hall', ['class-plug'])..device_ids = [memberId];
    group.network = null;
    AppState().deviceGroups.add(group);
    group.prepareStates();

    await tester.runAsync(() => Settings.setLocalMode(true));
    await pumpGolden(tester, DetailPage(null, group), dark: false);
    final reading =
        group.states.firstWhere((s) => s.functionId == onOffFunction);
    reading.value = [true, true];
    group.notifyStateChanged();
    await tester.pump();

    expect(buttonOf(tester, 'Power').onPressed, isNull);
    expect(headerLanIcon(), findsOneWidget);
  });
}
