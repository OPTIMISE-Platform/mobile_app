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
import 'package:mobile_app/widgets/tabs/sensors/sensor_picker.dart';

import 'fake_backend.dart';
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

  testWidgets('an on/off reading is listed as a switch, before its controls',
      (tester) async {
    await warmUpMgwStorage(tester);
    final backend = FakeBackend();
    backend.serveJson('GET', '/device-repository/device-groups', 200, []);
    backend.serveJson('GET', '/device-repository/extended-hubs', 200, []);
    backend.serveJson('GET', '/device-repository/device-types', 200, []);
    backend.serveJson('GET', '/device-repository/user-device-types', 200, []);
    backend.serveDevicesPaged(
        [deviceJson('fan', 'Bathroom fan', deviceTypeId: 'plug')]);
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
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // After the picker's own metadata load, which replaces what it cannot
    // fetch.
    registerOnOffFunctions();
    AppState().deviceTypes['plug'] = plugType('plug');

    await tester.tap(find.text('Bathroom fan'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    IconData? leadingOf(String title) => (tester
            .widget<ListTile>(find.ancestor(
                of: find.text(title), matching: find.byType(ListTile)))
            .leading! as Icon)
        .icon;

    expect(leadingOf('Power'), Icons.toggle_on_outlined);
    expect(leadingOf('Switch on'), Icons.input);
    expect(leadingOf('Switch off'), Icons.input);
    expect(find.byIcon(Icons.show_chart), findsNothing);

    final rowTops = {
      for (final title in ['Power', 'Switch on', 'Switch off'])
        title: tester.getTopLeft(find.text(title)).dy,
    };
    expect(rowTops['Power']!, lessThan(rowTops['Switch on']!));
    expect(rowTops['Power']!, lessThan(rowTops['Switch off']!));

    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  });
}
