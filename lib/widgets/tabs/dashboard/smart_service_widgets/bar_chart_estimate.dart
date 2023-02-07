/*
 * Copyright 2022 InfAI (CC SES)
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
import 'package:flutter/widgets.dart';

import '../../../../theme.dart';
import 'bar_chart.dart';

class SmSeBarChartEstimate extends SmSeBarChart {

  @override
  void add2D(List<dynamic> values, {int colorOffset = 0}) {
    final precision = calcPrecision(values);
    for (int i = 0; i < values.length; i++) {
      final t = DateTime.parse(values[i][0]).millisecondsSinceEpoch;
      timestamps.add(values[i][0]);
      rawTimestamps.add(t.toInt());
      final List<BarChartRodData> rods = [];

      for (int j = 1; j < values[i].length; j += 2) {
        final List<BarChartRodStackItem> rodStackItems = [];

        final low = double.parse((0.0 + (values[i][j] ?? 0)).toStringAsFixed(precision));
        if (values[i][j] == null) values[i][j] = 0;
        rodStackItems.add(BarChartRodStackItem(0.0, low, MyTheme.getSomeColor(j - 1)));

        double? high;
        if (values[i][j + 1] != null) {
          high = double.parse((0.0 + values[i][j + 1]).toStringAsPrecision(precision));
          rodStackItems.add(BarChartRodStackItem(low, high, getSpecialColor(j - 1)));
        }

        rods.add(BarChartRodData(
            toY: high ?? low, rodStackItems: rodStackItems, width: 20, borderRadius: const BorderRadius.horizontal()));
      }

      if (rods.isNotEmpty) {
        barGroups.add(BarChartGroupData(
          x: t,
          barRods: rods,
        ));
      }
    }
    barGroups.sort((a, b) => a.x - b.x);
    rawTimestamps.sort();
    setDateFormat(timestamps);
  }
}
