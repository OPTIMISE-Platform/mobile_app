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

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/shared/chart.dart';

import 'golden_helper.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  // A tall, finely stepped axis with a unit suffix: "1.24 kWh" is wider than
  // the 30px reserve and used to wrap into two lines.
  testWidgets("left titles wider than the reserve stay on one line",
      (tester) async {
    await pumpGolden(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => SizedBox(
            width: 300,
            height: 800,
            child: LineChart(LineChartData(
              lineBarsData: [
                LineChartBarData(spots: const [FlSpot(0, 1.0), FlSpot(1, 1.5)])
              ],
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                bottomTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                    sideTitles:
                        BaseChartFormatter.getLeftTitles(context, suffix: "kWh")),
              ),
            )),
          ),
        ),
      ),
      dark: false,
    );

    final labels = find.descendant(
        of: find.byType(LineChart), matching: find.textContaining("kWh"));
    expect(labels.evaluate().length, greaterThan(3));
    final lineHeight = tester.getSize(labels.first).height;
    expect(lineHeight, lessThan(18), reason: "one line of 12sp text");
    for (final label in labels.evaluate()) {
      expect(tester.getSize(find.byWidget(label.widget)).height, lineHeight);
    }
  });
}
