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

@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/location.dart';
import 'package:mobile_app/widgets/tabs/device_tabs.dart';
import 'package:mobile_app/widgets/tabs/locations/location_page.dart';

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

  // Both themes in one test - see golden_device_tabs_shell_test.dart for why.
  testWidgets("location page", (tester) async {
    for (final dark in [false, true]) {
      final suffix = dark ? "dark" : "light";

      final backend = FakeBackend();
      backend.serveJson("GET", "/device-repository/extended-devices", 200,
          [deviceJson("device-1", "Living room lamp")]);
      serveGoldenBackend(backend);
      await warmUpMgwStorage(tester);

      AppState().locations.add(
          Location("location-1", "Ground floor", "", "", ["device-1"], []));

      // An unmounted DeviceTabsState() works: LocationPage only reads its
      // .filter field.
      await pumpGolden(
        tester,
        LocationPage(0, DeviceTabsState()),
        dark: dark,
      );
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile("goldens/location_page_$suffix.png"));

      resetAppStateForGolden();
      resetGoldenBackend();
    }
  });
}
