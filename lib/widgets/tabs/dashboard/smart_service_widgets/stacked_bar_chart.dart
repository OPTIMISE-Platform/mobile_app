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
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/bar_chart.dart';

import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/indicator.dart';
import 'package:mobile_app/widgets/tabs/dashboard/dashboard.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/shared/chart.dart';

class SmSeStackedBarChart extends SmSeBarChart {
  int touchedIndex = -1;
  List<dynamic> values = [];

  bool maximized = false;

  @override
  setPreview(bool enabled) {
    preview = enabled;
    if (enabled || !maximized) {
      height = 7.0;
      if (!enabled) height++;
    } else {
      height = 8.0 + (titles.length * .5);
    }
  }

  @override
  Widget buildInternal(BuildContext context, bool parentFlexible) {
    return StatefulBuilder(builder: (context, setState) {
      final List<Widget> legendWidgets = [];

      if (!preview && maximized) {
        for (int i = 0; i < titles.length; i++) {
          legendWidgets.addAll([
            GestureDetector(
                onTapDown: (_) => setState(() => touchedIndex = i),
                onTapUp: (_) => setState(() => touchedIndex = -1),
                onTapCancel: () => setState(() => touchedIndex = -1),
                child: Indicator(
                  color: MyTheme.getSomeColor(i),
                  text: titles[i],
                  textColor: MyTheme.textColor!,
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
          : Column(children: [
              Container(
                  height: 8 * heightUnit - MyTheme.insetSize,
                  padding: const EdgeInsets.only(
                      top: MyTheme.insetSize, right: MyTheme.insetSize, left: MyTheme.insetSize / 2, bottom: MyTheme.insetSize / 2),
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
                  )),
              Expanded(
                  child: Stack(children: [
                Container(
                  constraints: BoxConstraints(minHeight: 12, minWidth: MediaQuery.of(context).size.width),
                  child: Column(children: legendWidgets),
                ),
                preview
                    ? const SizedBox.shrink()
                    : Positioned(
                        bottom: 4,
                        right: 12,
                        child: IconButton(
                            onPressed: () => setState(() {
                                  maximized = !maximized;
                                  setPreview(preview);
                                  redrawDashboard(context);
                                }),
                            icon: Icon(maximized ? Icons.zoom_in_map : Icons.zoom_out_map)))
              ])),
            ]);
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
