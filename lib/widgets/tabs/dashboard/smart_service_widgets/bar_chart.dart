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

import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/line_chart.dart';

import '../../../../theme.dart';
import '../dashboard.dart';

class SmSeBarChart extends SmSeLineChart {
  final List<BarChartGroupData> _barGroups = [];

  @override
  Future<void> refreshInternal() async {
    _barGroups.clear();
    final resp = await request.perform();
    if (resp.statusCode > 299) {
      return;
    } else {
      final List<dynamic> respArr = json.decode(resp.body);
      if (respArr.isEmpty) return;
      if (respArr[0] is! List || respArr[0].isEmpty) return;
      if (respArr[0][0] is List) {
        int linesAdded = 0;
        for (int i = 0; i < respArr.length; i++) {
          if (respArr[i].isEmpty) continue;
          _add2D(respArr[i], colorOffset: linesAdded);
          linesAdded += (respArr[i][0] as List).length - 1;
        }
      } else {
        _add2D(respArr);
      }
    }
  }

  @override
  Widget buildInternal(BuildContext context, bool previewOnly, bool parentFlexible) {
    final Widget w = _barGroups.isEmpty
        ? const Center(child: Text("No Data"))
        : Container(
            height: height * heightUnit - MyTheme.insetSize,
            padding:
                const EdgeInsets.only(top: MyTheme.insetSize, right: MyTheme.insetSize, left: MyTheme.insetSize / 2, bottom: MyTheme.insetSize / 2),
            child: BarChart(
              BarChartData(
                  borderData: FlBorderData(show: false),
                  barGroups: _barGroups,
                  titlesData: FlTitlesData(
                    show: true,
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: false,
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 14,
                          getTitlesWidget: (val, meta) {
                            if (val == meta.max || val == meta.min) {
                              return const SizedBox.shrink();
                            }
                            final dt = DateTime.fromMillisecondsSinceEpoch(val.floor()).toLocal();
                            return Container(
                                padding: const EdgeInsets.only(top: 3),
                                child: Text(dateFormat.format(dt), style: TextStyle(fontSize: MediaQuery.textScaleFactorOf(context) * 11)));
                          }),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 24,
                          getTitlesWidget: (val, meta) {
                            if (val == meta.max || val == meta.min) {
                              return const SizedBox.shrink();
                            }
                            return Text(meta.formattedValue, style: TextStyle(fontSize: MediaQuery.textScaleFactorOf(context) * 11));
                          }),
                    ),
                  ),
                  barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                          getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                              BarTooltipItem("${rodIndex < titles.length ? "${titles[rodIndex]}\n" : ""}${rod.toY}", TextStyle(color: rod.color))))),
              swapAnimationDuration: const Duration(milliseconds: 400),
            ));
    return parentFlexible ? Expanded(child: w) : w;
  }

  void _add2D(List<dynamic> values, {int colorOffset = 0}) {
    final precision = calcPrecision(values);
    final List<String> timestamps = [];
    for (int i = 0; i < values.length; i++) {
      final t = DateTime.parse(values[i][0]).millisecondsSinceEpoch;
      timestamps.add(values[i][0]);
      final rods = (values[i] as List)
          .skip(1)
          .where((element) => element != 0.0 && element != null && element != 0)
          .toList(growable: false)
          .asMap()
          .entries
          .map<BarChartRodData>((e) => BarChartRodData(
              toY: double.parse((e.value is int ? e.value.toDouble() : e.value ?? 0).toStringAsFixed(precision)), color: MyTheme.getSomeColor(e.key)))
          .toList(growable: false);
      if (rods.isNotEmpty) {
        _barGroups.add(BarChartGroupData(
          x: t,
          barRods: rods,
        ));
      }
    }
    setDateFormat(timestamps);
  }
}
