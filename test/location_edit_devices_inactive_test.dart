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
import 'package:mobile_app/models/location.dart';
import 'package:mobile_app/widgets/tabs/locations/location_edit_devices.dart';

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

  testWidgets(
      "an inactive member stays listed, selected, and can be deselected",
      (tester) async {
    final backend = FakeBackend();
    backend.serveJson("GET", "/device-repository/device-groups", 200, []);
    backend.serveJson("GET", "/device-repository/extended-hubs", 200, []);
    backend.serveJson("GET", "/device-repository/device-types", 200, []);
    backend.serveJson("GET", "/device-repository/user-device-types", 200, []);
    backend.serveDevicesPaged([
      deviceJson("active-1", "Kettle"),
      deviceJson("inactive-1", "Old fridge", inactive: true),
    ]);
    serveGoldenBackend(backend);
    await warmUpMgwStorage(tester);
    AppState().locations.add(Location(
        "location-1", "Kitchen", "", "", ["active-1", "inactive-1"], []));

    await pumpGolden(tester, LocationEditDevices(0), dark: false);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    Icon iconOf(String name) => tester.widget<Icon>(find.descendant(
        of: find.ancestor(of: find.text(name), matching: find.byType(ListTile)),
        matching: find.byType(Icon)));

    expect(find.text("Old fridge"), findsOneWidget);
    expect(iconOf("Old fridge").icon, Icons.check_circle);

    await tester.tap(find.text("Old fridge"));
    await tester.pump();

    expect(find.text("Old fridge"), findsOneWidget);
    expect(iconOf("Old fridge").icon, Icons.circle_outlined);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  });
}
