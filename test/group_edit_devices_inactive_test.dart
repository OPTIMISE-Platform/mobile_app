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

// Own file, not group_edit_devices_selection_test.dart: a second widget test
// in that process never got its group-helper response, the memoized-setup
// pattern docs/testing.md describes.
void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  testWidgets(
      "a selected member missing from the device list, such as an inactive "
      "one, shows its name and can be deselected", (tester) async {
    final backend = FakeBackend();
    backend.serveJson("POST", "/device-selection/device-group-helper", 200, {
      "options": [
        {"device": deviceJson("device-1", "Living room lamp"), "removes_criteria": []},
      ],
      "criteria": [],
    });
    backend.serveDevicesPaged([
      deviceJson("inactive-1", "Old heater", inactive: true),
    ]);
    serveGoldenBackend(backend);
    // Not in AppState().devices: the device search hides it.
    final group =
        DeviceGroup("group-1", "Ground floor", null, "", ["inactive-1"], null);
    await pumpGolden(tester, GroupEditDevices(group), dark: false);

    expect(find.text("Selected"), findsOneWidget);
    expect(find.text("MISSING_DEVICE_NAME"), findsNothing);
    expect(find.text("Old heater"), findsOneWidget);

    await tester.tap(find.text("Old heater"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text("Selected"), findsNothing);
    expect(find.text("Old heater"), findsNothing);
  });
}
