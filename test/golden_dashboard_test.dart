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
import 'package:mobile_app/models/smart_service.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/keyed_list.dart';
import 'package:mobile_app/widgets/tabs/dashboard/dashboard.dart';

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
  testWidgets("dashboard", (tester) async {
    for (final dark in [false, true]) {
      final suffix = dark ? "dark" : "light";

      final backend = FakeBackend();
      // Uncaught in the widget itself - must be served. A "text" widget needs
      // no further request of its own.
      backend.serveJson("GET", "/smart-services/repository/modules", 200, [
        {
          "design_id": "design-1",
          "id": "module-1",
          "instance_id": "instance-1",
          "release_id": "release-1",
          "user_id": "user-1",
          "module_type": "widget",
          "module_data": {
            "widget_type": "text",
            "widget_data": {"text": "Energy today: 4.2 kWh"},
          },
        },
      ]);
      serveGoldenBackend(backend);

      // Kept consistent with the served module, or Dashboard's cleanup timer
      // (missing widget -> re-check after 5s) fires mid-test.
      final dashboard = SmartServiceDashboard(
          "dashboard-1", "Home", [Pair("module-1", "instance-1")]);
      await tester.runAsync(() => Settings.setSmartServiceDashboards([dashboard]));

      await pumpGolden(tester, const Dashboard(), dark: dark);
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile("goldens/dashboard_$suffix.png"));

      resetAppStateForGolden();
      resetGoldenBackend();
    }
  });
}
