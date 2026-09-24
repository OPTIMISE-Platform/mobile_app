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
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/base.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/shared/widget_info.dart';

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

  Future<void> renderWidget(
    WidgetTester tester,
    String name,
    Map<String, dynamic> widgetData, {
    required bool dark,
    Duration settle = const Duration(milliseconds: 100),
  }) async {
    final w = (await SmartServiceModuleWidget.fromWidgetInfo(
        name, WidgetInfo.fromJson(widgetData)))!;
    // Not a bare await: refresh() issues its request via plain Dio/await,
    // outside any pumped widget callback, and nothing then drives the fake
    // clock/microtask queue that its response needs - runAsync gives it the
    // real event loop instead (see golden_device_tabs_shell_test.dart for
    // the sibling pitfall, a memoized Future awaited across test zones).
    await tester.runAsync(() => w.refresh());
    await pumpGolden(
      tester,
      Scaffold(body: Builder(builder: (c) => w.build(c, false))),
      dark: dark,
      settle: settle,
    );
    final suffix = dark ? "dark" : "light";
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile("goldens/smart_service_${name}_$suffix.png"));
  }

  // Every widget in one test, both themes - see
  // golden_device_tabs_shell_test.dart for why they share a test/zone.
  testWidgets("smart service chart widgets", (tester) async {
    for (final dark in [false, true]) {
      final backend = FakeBackend();
      // A single, flat series: two points, same value. Real time never
      // enters these widgets' own axes (unlike the sparkline card), but
      // keeping the series flat also sidesteps the pv_forecast widget's
      // un-awaited sun-icon lookup (only added for a *rising* segment).
      backend.serveJson("GET", "/widget-data/line", 200, [
        ["2026-01-01T10:00:00.000Z", 10.0],
        ["2026-01-01T11:00:00.000Z", 12.0],
      ]);
      backend.serveJson("GET", "/widget-data/bar", 200, [
        ["2026-01-01T10:00:00.000Z", 10.0],
        ["2026-01-01T11:00:00.000Z", 12.0],
      ]);
      backend.serveJson("GET", "/widget-data/stacked-bar", 200, [
        ["2026-01-01T10:00:00.000Z", 4.0, 6.0],
        ["2026-01-01T11:00:00.000Z", 5.0, 7.0],
      ]);
      backend.serveJson("GET", "/widget-data/pie", 200, [
        ["2026-01-01T10:00:00.000Z", 30.0, 45.0, 25.0],
      ]);
      serveGoldenBackend(backend);

      await renderWidget(tester, "line_chart", {
        "widget_type": "line_chart",
        "widget_data": {"request": request("/widget-data/line"), "titles": ["Power"]},
      }, dark: dark);

      await renderWidget(tester, "bar_chart", {
        "widget_type": "bar_chart",
        "widget_data": {"request": request("/widget-data/bar"), "titles": ["Power"]},
      }, dark: dark);

      await renderWidget(tester, "stacked_bar_chart", {
        "widget_type": "stacked_bar_chart",
        "widget_data": {
          "request": request("/widget-data/stacked-bar"),
          "titles": ["Solar", "Grid"],
        },
      }, dark: dark);

      await renderWidget(
        tester,
        "pie_chart",
        {
          "widget_type": "pie_chart",
          "widget_data": {
            "request": request("/widget-data/pie"),
            "titles": ["Solar", "Grid", "Battery"],
            "showSum": true,
            "sumUnit": "kWh",
          },
        },
        dark: dark,
        settle: const Duration(milliseconds: 150),
      );

      resetAppStateForGolden();
      resetGoldenBackend();
    }
  });
}
