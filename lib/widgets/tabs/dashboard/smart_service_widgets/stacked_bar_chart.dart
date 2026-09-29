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

import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/bar_chart.dart';

import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/indicator.dart';
import 'package:mobile_app/widgets/tabs/dashboard/dashboard.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/shared/chart.dart';

class SmSeStackedBarChart extends SmSeBarChart {
  int touchedIndex = -1;
  List<dynamic> values = [];

  // One legend row at text scale 1: the 16px Indicator plus the 4px gap. Larger
  // text makes rows taller; the chart area gives way instead of overflowing.
  static const _legendRowHeight = 20.0;

  @override
  setPreview(bool enabled) {
    preview = enabled;
    if (enabled) {
      height = 7.0;
    } else {
      // The chart box is 8 units minus Spacing.md; the legend gets that
      // margin plus whatever the extra units add.
      final legendOverflow = titles.length * _legendRowHeight - Spacing.md;
      height = 8.0 + max(legendOverflow, 0) / heightUnit;
    }
  }

  @override
  Widget buildInternal(BuildContext context, bool parentFlexible) {
    return StatefulBuilder(builder: (context, setState) {
      final List<Widget> legendWidgets = [];

      if (!preview) {
        for (int i = 0; i < titles.length; i++) {
          legendWidgets.addAll([
            GestureDetector(
                onTapDown: (_) => setState(() => touchedIndex = i),
                onTapUp: (_) => setState(() => touchedIndex = -1),
                onTapCancel: () => setState(() => touchedIndex = -1),
                child: Indicator(
                  color: MyTheme.getSomeColor(i),
                  text: titles[i],
                  textColor: context.appColors.text,
                  isSquare: true,
                )),
            const SizedBox(
              height: 4,
            )
          ]);
        }
      }

      buildGroups(); // Do this here for highlighting

      final Widget w = barGroups.isEmpty
          ? const Center(child: Text("No Data"))
          : LayoutBuilder(builder: (context, constraints) => Column(children: [
              Expanded(child: Container(
                  padding: const EdgeInsets.only(
                      top: Spacing.md, right: Spacing.md, left: Spacing.xs, bottom: Spacing.xs),
                  child: gestureDetector(
                    context,
                    BarChart(
                      BarChartData(
                          borderData: FlBorderData(show: false),
                          barGroups: barGroups.where((e) => e.x >= left && e.x <= right).toList(),
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
                              sideTitles: BaseChartFormatter.getBottomTitles(context, dateFormat)
                            ),
                            leftTitles: AxisTitles(
                              sideTitles: BaseChartFormatter.getLeftTitles(context)
                            ),
                          ),
                          barTouchData: BarTouchData(enabled: false)),
                      swapAnimationDuration: Duration.zero,
                    ),
                  ))),
              if (legendWidgets.isNotEmpty)
                // Scrolls past half the widget instead of pushing the chart
                // out: rows grow with the text scale.
                ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: constraints.maxHeight / 2),
                    child: SingleChildScrollView(
                        child: Container(
                            padding: const EdgeInsets.only(left: Spacing.md),
                            width: double.infinity,
                            child: Column(children: legendWidgets)))),
            ]));
      return parentFlexible ? Expanded(child: w) : w;
    });
  }

  @override
  void add2D(List<dynamic> values, {int colorOffset = 0}) {
    this.values.addAll(values);
    buildGroups();
  }

  @override
  Future<void> refreshInternal() async {
    values.clear();
    await super.refreshInternal();
  }

  void buildGroups() {
    barGroups.clear();
    timestamps.clear();
    rawTimestamps.clear();
    for (int i = 0; i < values.length; i++) {
      double sum = 0.0;
      final t = DateTime.parse(values[i][0]).millisecondsSinceEpoch;
      final List<BarChartRodStackItem> rodStackItems = [];
      for (int j = 1; j < values[i].length; j++) {
        if (values[i][j] == null) values[i][j] = 0;
        rodStackItems
            .add(BarChartRodStackItem(sum, sum + values[i][j], MyTheme.getSomeColor(j - 1), BorderSide(width: touchedIndex == j - 1 ? 1.5 : 0)));
        sum += values[i][j];
      }

      timestamps.add(values[i][0]);
      rawTimestamps.add(t.toInt());
      final rod = BarChartRodData(toY: sum, rodStackItems: rodStackItems, width: 20, borderRadius: const BorderRadius.horizontal());
      if (rodStackItems.isNotEmpty) {
        barGroups.add(BarChartGroupData(
          x: t,
          barRods: [rod],
        ));
      }
    }
    rawTimestamps.sort();
    barGroups.sort((a, b) => a.x - b.x);
    setDateFormat(timestamps, rawTimestamps);
  }
}
