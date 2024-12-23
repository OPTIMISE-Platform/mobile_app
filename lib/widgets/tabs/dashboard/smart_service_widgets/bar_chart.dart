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
import 'package:flutter/material.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/line_chart.dart';

import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/tabs/dashboard/dashboard.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/shared/chart.dart';

class SmSeBarChart extends SmSeLineChart {
  final List<BarChartGroupData> barGroups = [];

  bool colorLatestSpecial = false;
  static const double specialColorMultiplier = 0.7;

  @override
  @mustCallSuper
  Future<void> configure(dynamic data) async {
    super.configure(data);
    colorLatestSpecial = data["color_latest_special"] ?? colorLatestSpecial;
  }

  @override
  Future<void> refreshInternal() async {
    barGroups.clear();
    await super.refreshInternal();
  }

  @override
  Widget buildInternal(BuildContext context, bool parentFlexible) {
    final Widget w = barGroups.isEmpty
        ? const Center(child: Text("No Data"))
        : Container(
            height: height * heightUnit - MyTheme.insetSize,
            padding: const EdgeInsets.only(
                top: MyTheme.insetSize,
                right: MyTheme.insetSize,
                left: MyTheme.insetSize / 2,
                bottom: MyTheme.insetSize / 2),
            child: gestureDetector(
                context,
                BarChart(
                  BarChartData(
                      borderData: FlBorderData(show: false),
                      barGroups: barGroups
                          .where((element) =>
                              element.x >= left && element.x <= right)
                          .toList(),
                      titlesData: FlTitlesData(
                        show: true,
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: false,
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: (rawTimestamps.length < 10 &&
                                      MediaQuery.of(context).orientation ==
                                          Orientation.portrait) ||
                                  (rawTimestamps.length < 21 &&
                                      MediaQuery.of(context).orientation ==
                                          Orientation.landscape)
                              ? BaseChartFormatter.getBottomTitles(
                                  context, dateFormat)
                              : BaseChartFormatter.getBottomTitles(
                                  context, dateFormat,
                                  rotated: true, reservedSize: 50),
                        ),
                        leftTitles: AxisTitles(
                            sideTitles:
                                BaseChartFormatter.getLeftTitles(context)),
                      ),
                      barTouchData: BarTouchData(
                          enabled: !preview,
                          touchTooltipData: BarTouchTooltipData(
                              fitInsideHorizontally: true,
                              fitInsideVertically: true,
                              getTooltipItem: (group, groupIndex, rod,
                                      rodIndex) =>
                                  BarTooltipItem(
                                      "${rodIndex < titles.length ? "${titles[rodIndex]}\n" : ""}${rod.toY}",
                                      TextStyle(color: rod.color))))),
                  swapAnimationDuration: Duration.zero,
                )));
    return parentFlexible ? Expanded(child: w) : w;
  }

  @override
  void add2D(List<dynamic> values, {int colorOffset = 0}) {
    final precision = calcPrecision(values);
    for (int i = 0; i < values.length; i++) {
      final t = DateTime.parse(values[i][0]).millisecondsSinceEpoch;
      timestamps.add(values[i][0]);
      rawTimestamps.add(t.toInt());
      final rods = (values[i] as List)
          .skip(1)
          .where((element) => element != 0.0 && element != null && element != 0)
          .toList(growable: false)
          .asMap()
          .entries
          .map<BarChartRodData>((e) => BarChartRodData(
              toY: double.parse(
                  (e.value is int ? e.value.toDouble() : e.value ?? 0)
                      .toStringAsFixed(precision)),
              color: i == values.length - 1 &&
                      colorLatestSpecial &&
                      initialTimestampDifference == null
                  ? getSpecialColor(e.key)
                  : MyTheme.getSomeColor(e.key),
              width: 20,
              borderRadius: const BorderRadius.horizontal()))
          .toList(growable: false);
      if (rods.isNotEmpty) {
        barGroups.add(BarChartGroupData(
          x: t,
          barRods: rods,
        ));
      }
    }
    barGroups.sort((a, b) => a.x - b.x);
    rawTimestamps.sort();
    final cutOff = barGroups.length - 12;
    if (cutOff > 0) {
      barGroups.removeRange(0, cutOff);
      timestamps.removeRange(0, cutOff);
      rawTimestamps.removeRange(0, cutOff);
    }
    setDateFormat(timestamps, rawTimestamps);
  }

  Color getSpecialColor(int key) {
    return MyTheme.getSomeColor(key)
        .withRed(
            (MyTheme.getSomeColor(key).red * specialColorMultiplier).toInt())
        .withGreen(
            (MyTheme.getSomeColor(key).green * specialColorMultiplier).toInt())
        .withBlue(
            (MyTheme.getSomeColor(key).blue * specialColorMultiplier).toInt());
  }
}
