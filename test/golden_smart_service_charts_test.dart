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

  // A day of hourly points: points within one hour give every x label the
  // same text.
  List<List<dynamic>> hourlySeries(List<double> values) => List.generate(
      values.length,
      (i) => [DateTime.utc(2026, 1, 1, i).toIso8601String(), values[i]]);

  // Zero overnight, peak at noon.
  const diurnalCurve = [
    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 2.0, 4.0, 7.0, 9.0, 11.0, 12.0, //
    12.0, 11.0, 9.0, 7.0, 4.0, 2.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
  ];

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
      backend.serveJson("GET", "/widget-data/line", 200, hourlySeries(diurnalCurve));
      backend.serveJson("GET", "/widget-data/bar", 200, hourlySeries(diurnalCurve));
      backend.serveJson("GET", "/widget-data/stacked-bar", 200, [
        ["2026-01-01T10:00:00.000Z", 4.0, 6.0],
        ["2026-01-01T11:00:00.000Z", 5.0, 7.0],
      ]);
      backend.serveJson("GET", "/widget-data/pie", 200, [
        ["2026-01-01T10:00:00.000Z", 30.0, 45.0, 25.0],
      ]);
      // Needs a rising segment for a recommendation and a sun marker.
      // Fractions; the widget multiplies by 100.
      backend.serveJson("GET", "/widget-data/pv-forecast", 200, hourlySeries(const [
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.05, 0.15, 0.35, 0.55, 0.75, 0.9, //
        0.9, 0.75, 0.55, 0.35, 0.15, 0.05, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
      ]));
      // One low/high pair per series and hour.
      backend.serveJson("GET", "/widget-data/bar-estimate", 200, [
        ["2026-01-01T00:00:00.000Z", 2.0, 4.0],
        ["2026-01-01T01:00:00.000Z", 1.0, 3.0],
        ["2026-01-01T02:00:00.000Z", 0.0, 2.0],
        ["2026-01-01T03:00:00.000Z", 1.0, 3.0],
        ["2026-01-01T04:00:00.000Z", 3.0, 5.0],
        ["2026-01-01T05:00:00.000Z", 5.0, 7.0],
      ]);
      // pv_flow parses each response body with double.parse.
      backend.serveJson("GET", "/widget-data/pv-flow/solar", 200, "500",
          contentType: Headers.textPlainContentType);
      backend.serveJson("GET", "/widget-data/pv-flow/charge", 200, "150",
          contentType: Headers.textPlainContentType);
      backend.serveJson("GET", "/widget-data/pv-flow/grid", 200, "80",
          contentType: Headers.textPlainContentType);
      backend.serveJson("GET", "/widget-data/pv-flow/battery", 200, "72",
          contentType: Headers.textPlainContentType);
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

      // This LineChart animates for 400ms, the other charts not at all.
      await renderWidget(
        tester,
        "pv_forecast",
        {
          "widget_type": "pv_forecast",
          "widget_data": {"request": request("/widget-data/pv-forecast")},
        },
        dark: dark,
        settle: const Duration(milliseconds: 450),
      );

      await renderWidget(tester, "bar_chart_estimate", {
        "widget_type": "bar_chart_estimate",
        "widget_data": {
          "request": request("/widget-data/bar-estimate"),
          "titles": ["Estimate"],
        },
      }, dark: dark);

      // Its ticker never stops, which is fine: pumpGolden does not settle.
      await renderWidget(tester, "pv_flow", {
        "widget_type": "pv_flow",
        "widget_data": {
          "chargingViaInverter": false,
          "solarGenerationRequest": request("/widget-data/pv-flow/solar"),
          "chargePowerRequest": request("/widget-data/pv-flow/charge"),
          "gridConsumptionRequests": [request("/widget-data/pv-flow/grid")],
          "batteryLevelRequest": request("/widget-data/pv-flow/battery"),
        },
      }, dark: dark);

      resetAppStateForGolden();
      resetGoldenBackend();
    }
  });
}
