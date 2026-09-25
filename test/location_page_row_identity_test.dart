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
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/models/location.dart';
import 'package:mobile_app/widgets/tabs/device_tabs.dart';
import 'package:mobile_app/widgets/tabs/locations/location_page.dart';
import 'package:mobile_app/widgets/tabs/shared/device_list_item.dart';

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

  // Two matching on/off-like states, so DeviceListItem renders the
  // expand/collapse toggle instead of a single inline icon.
  void makeMultiToggle(DeviceInstance device) {
    for (final serviceGroup in ["sg-1", "sg-2"]) {
      device.states.add(DeviceState(
        true,
        "service-$serviceGroup",
        serviceGroup,
        dotenv.env["FUNCTION_GET_ON_OFF_STATE"]!,
        "aspect-1",
        false,
        null,
        null,
        device.id,
        "path",
        "group",
      ));
    }
    device.notifyStateChanged();
  }

  testWidgets(
      "an expanded device row keeps its own state when removing a group "
      "collapses the section headers", (tester) async {
    final backend = FakeBackend();
    backend.serveJson("GET", "/device-repository/extended-devices", 200, [
      deviceJson("device-a", "Device A"),
      deviceJson("device-b", "Device B"),
    ]);
    serveGoldenBackend(backend);
    await warmUpMgwStorage(tester);

    AppState()
        .deviceGroups
        .add(DeviceGroup("group-1", "Group", null, "", [], null));
    AppState().locations.add(Location("location-1", "Ground floor", "", "",
        ["device-a", "device-b"], ["group-1"]));

    await pumpGolden(tester, LocationPage(0, DeviceTabsState()), dark: false);

    makeMultiToggle(AppState().devices.firstWhere((d) => d.id == "device-a"));
    makeMultiToggle(AppState().devices.firstWhere((d) => d.id == "device-b"));
    await tester.pump();

    // Both a device and a group section: headers are showing.
    expect(find.text("Devices"), findsOneWidget);
    expect(find.text("Groups"), findsOneWidget);

    final deviceARow = find.ancestor(
        of: find.text("Device A"), matching: find.byType(DeviceListItem));
    await tester.tap(find.descendant(
        of: deviceARow, matching: find.byIcon(Icons.expand_more)));
    await tester.pump();
    expect(
        find.descendant(
            of: deviceARow, matching: find.byIcon(Icons.expand_less)),
        findsOneWidget);

    // Removing the only group drops both section headers and shifts every
    // row two slots up.
    AppState().deviceGroups.clear();
    AppState().notifyListeners();
    await tester.pump();

    expect(find.text("Devices"), findsNothing);
    expect(find.text("Groups"), findsNothing);

    final deviceARowAfter = find.ancestor(
        of: find.text("Device A"), matching: find.byType(DeviceListItem));
    final deviceBRowAfter = find.ancestor(
        of: find.text("Device B"), matching: find.byType(DeviceListItem));

    expect(
        find.descendant(
            of: deviceARowAfter, matching: find.byIcon(Icons.expand_less)),
        findsOneWidget,
        reason: "device A's expanded state should follow device A");
    expect(
        find.descendant(
            of: deviceBRowAfter, matching: find.byIcon(Icons.expand_less)),
        findsNothing,
        reason: "device B must not inherit device A's expanded state");
    expect(
        find.descendant(
            of: deviceBRowAfter, matching: find.byIcon(Icons.expand_more)),
        findsOneWidget,
        reason: "device B should stay collapsed");
  });
}
