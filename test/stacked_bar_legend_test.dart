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
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/indicator.dart';
import 'package:mobile_app/widgets/tabs/dashboard/dashboard.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/stacked_bar_chart.dart';

import 'golden_helper.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  SmSeStackedBarChart chartWith(int titles) => SmSeStackedBarChart()
    ..titles.addAll([for (var i = 0; i < titles; i++) "Series $i"]);

  // The chart box is 8 units minus Spacing.md; the rest of the widget is what
  // the legend gets.
  double legendSpace(SmSeStackedBarChart chart) =>
      chart.height * heightUnit - (8 * heightUnit - Spacing.md);

  test("the legend has room for every title at text scale 1", () {
    for (var n = 0; n <= 8; n++) {
      final chart = chartWith(n)..setPreview(false);
      expect(legendSpace(chart), greaterThanOrEqualTo(n * 20.0),
          reason: "$n titles");
    }
  });

  test("without titles the widget keeps its 8 units", () {
    final chart = chartWith(0)..setPreview(false);
    expect(chart.height, 8);
  });

  test("the height grows by no more than the legend needs", () {
    final chart = chartWith(6)..setPreview(false);
    expect(legendSpace(chart) - 6 * 20.0, lessThan(heightUnit));
  });

  test("the preview stays at 7 units with no legend space", () {
    final chart = chartWith(4)..setPreview(true);
    expect(chart.height, 7);
  });

  // Rows grow with the text scale, so the height computed for scale 1 is too
  // small for them; the widget must give the room from the chart instead.
  for (final scale in [1.0, 1.3, 2.0]) {
    for (final n in [2, 4, 6, 12]) {
      testWidgets("$n series at text scale $scale: no overflow, legend complete",
          (tester) async {
        final t0 = DateTime.utc(2026, 1, 1, 10);
        final chart = chartWith(n);
        chart.add2D([
          for (var h = 0; h < 2; h++)
            [
              t0.add(Duration(hours: h)).toIso8601String(),
              for (var i = 0; i < n; i++) 1.0 + i,
            ]
        ]);
        chart.left = t0.millisecondsSinceEpoch;
        chart.right = t0.add(const Duration(hours: 1)).millisecondsSinceEpoch;

        final errors = <FlutterErrorDetails>[];
        final oldOnError = FlutterError.onError;
        FlutterError.onError = (d) => errors.add(d);

        await pumpGolden(
          tester,
          Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: Scaffold(body: Builder(builder: (c) => chart.build(c, false))),
            ),
          ),
          dark: false,
        );
        await tester.pump(const Duration(milliseconds: 100));

        FlutterError.onError = oldOnError;
        expect(errors, isEmpty,
            reason: errors.map((e) => e.exceptionAsString()).join('\n'));
        // Scrolled-off rows still exist in the tree, so all n are found.
        expect(find.byType(Indicator, skipOffstage: false), findsNWidgets(n));
      });
    }
  }
}
