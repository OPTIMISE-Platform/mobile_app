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

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/widgets/tabs/groups/group_edit_devices.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  // Non-empty criteria and removesCriteria: false route a tap through the
  // synchronous candidate -> selected move, the branch whose index
  // arithmetic this test guards.
  FakeBackend candidatesBackend() {
    final backend = FakeBackend();
    backend.serveJson("POST", "/device-selection/device-group-helper", 200, {
      "options": [
        {"device": deviceJson("device-1", "Living room lamp"), "removes_criteria": []},
        {"device": deviceJson("device-2", "Heat pump"), "removes_criteria": []},
      ],
      "criteria": [
        {"aspect_id": "a", "device_class_id": "c", "function_id": "f", "interaction": "i"},
      ],
    });
    return backend;
  }

  testWidgets(
      "selecting candidates one at a time moves the right device each time",
      (tester) async {
    serveGoldenBackend(candidatesBackend());
    final group = DeviceGroup("group-1", "Ground floor", null, "", [], null);
    await pumpGolden(tester, GroupEditDevices(group), dark: false);

    // Only the candidates section: nothing selected yet.
    expect(find.text("Selected"), findsNothing);
    expect(find.text("Candidates"), findsOneWidget);
    expect(find.text("Living room lamp"), findsOneWidget);
    expect(find.text("Heat pump"), findsOneWidget);

    // Tap the *second* candidate first: a select that removes anything but
    // index 0 from _candidates is what the removal's index arithmetic has
    // to get right.
    await tester.tap(find.text("Heat pump"));
    await tester.pump();

    // Heat pump moved to Selected; Living room lamp is still the only
    // candidate, not removed instead of it.
    expect(find.text("Selected"), findsOneWidget);
    expect(find.text("Candidates"), findsOneWidget);
    expect(find.text("Living room lamp"), findsOneWidget);
    expect(find.text("Heat pump"), findsOneWidget);

    await tester.tap(find.text("Living room lamp"));
    await tester.pump();

    // Both selected: no candidates left, so that section (and its header)
    // is gone.
    expect(find.text("Selected"), findsOneWidget);
    expect(find.text("Candidates"), findsNothing);
    expect(find.text("Living room lamp"), findsOneWidget);
    expect(find.text("Heat pump"), findsOneWidget);
  });
}
