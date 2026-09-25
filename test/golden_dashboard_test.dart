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

import 'package:dio/dio.dart';
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

  Map<String, dynamic> request(String path) =>
      {"method": "GET", "url": "https://api.test$path", "body": null, "need_token": false};

  Map<String, dynamic> module(String id, String instanceId, String widgetType,
          Map<String, dynamic> widgetData) =>
      {
        "design_id": "design-1",
        "id": id,
        "instance_id": instanceId,
        "release_id": "release-1",
        "user_id": "user-1",
        "module_type": "widget",
        "module_data": {"widget_type": widgetType, "widget_data": widgetData},
      };

  // Both themes in one test - see golden_device_tabs_shell_test.dart for why.
  testWidgets("dashboard", (tester) async {
    for (final dark in [false, true]) {
      final suffix = dark ? "dark" : "light";

      final backend = FakeBackend();
      // Four widget kinds: text (no request of its own), a fetched single
      // value, a chart and an icon.
      backend.serveJson("GET", "/smart-services/repository/modules", 200, [
        module("module-1", "instance-1", "text",
            {"text": "Energy today: 4.2 kWh"}),
        module("module-2", "instance-2", "single_value",
            {"request": request("/widget-data/single-value")}),
        module("module-3", "instance-3", "line_chart", {
          "request": request("/widget-data/dashboard-line"),
          "titles": ["Power"],
        }),
        module("module-4", "instance-4", "icon", {"icon_name": "lightbulb"}),
      ]);
      backend.serveJson("GET", "/widget-data/single-value", 200, "22.5 °C",
          contentType: Headers.textPlainContentType);
      // A day of hourly points: points within one hour give every x label
      // the same text.
      backend.serveJson("GET", "/widget-data/dashboard-line", 200, [
        for (var h = 0; h < 24; h++)
          [DateTime.utc(2026, 1, 1, h).toIso8601String(), 18.0 + (h - 12).abs() / 3],
      ]);
      serveGoldenBackend(backend);

      // Kept consistent with the served modules, or Dashboard's cleanup timer
      // (missing widget -> re-check after 5s) fires mid-test.
      final dashboard = SmartServiceDashboard("dashboard-1", "Home", [
        Pair("module-1", "instance-1"),
        Pair("module-2", "instance-2"),
        Pair("module-3", "instance-3"),
        Pair("module-4", "instance-4"),
      ]);
      await tester.runAsync(() => Settings.setSmartServiceDashboards([dashboard]));

      await pumpGolden(tester, const Dashboard(), dark: dark);
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile("goldens/dashboard_$suffix.png"));

      resetAppStateForGolden();
      resetGoldenBackend();
    }
  });
}
