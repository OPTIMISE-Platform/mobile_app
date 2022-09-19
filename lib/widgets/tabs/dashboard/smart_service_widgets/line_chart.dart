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
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/shared/request.dart';

import '../../../../theme.dart';
import '../dashboard.dart';

class SmSeLineChart extends SmSeRequest {
  final List<LineChartBarData> _lines = [];

  @override
  double height = 5;

  @override
  double width = 5;

  @override
  Widget buildInternal(BuildContext context, bool previewOnly, bool parentFlexible) {
    final Widget w = _lines.isEmpty
        ? const Center(child: Text("No Data"))
        : Container(
            height: height * heightUnit - MyTheme.insetSize,
            //width: MediaQuery.of(context).size.width,
            padding:
                const EdgeInsets.only(top: MyTheme.insetSize, right: MyTheme.insetSize, left: MyTheme.insetSize / 2, bottom: MyTheme.insetSize / 2),
            child: LineChart(
              LineChartData(
                borderData: FlBorderData(show: false),
                lineBarsData: _lines,
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
                        //interval: 5 * 60 * 1000,
                        getTitlesWidget: (val, meta) {
                          if (val == meta.max || val == meta.min) {
                            return const SizedBox.shrink();
                          }
                          final dt = DateTime.fromMillisecondsSinceEpoch(val.floor()).toLocal();
                          return Container(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(MyTheme.formatHHMM.format(dt), style: TextStyle(fontSize: MediaQuery.textScaleFactorOf(context) * 11)));
                        }),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 18,
                        getTitlesWidget: (val, meta) {
                          if (val == meta.max || val == meta.min) {
                            return const SizedBox.shrink();
                          }
                          return Text(meta.formattedValue, style: TextStyle(fontSize: MediaQuery.textScaleFactorOf(context) * 11));
                        }),
                  ),
                ),
                lineTouchData: LineTouchData(
                    enabled: !previewOnly, touchTooltipData: LineTouchTooltipData(fitInsideVertically: true, fitInsideHorizontally: true)),
              ),
              swapAnimationDuration: const Duration(milliseconds: 400),
            ));
    return parentFlexible ? Expanded(child: w) : w;
  }

  @override
  Future<void> refreshInternal() async {
    _lines.clear();
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

  void _add2D(List<dynamic> values, {int colorOffset = 0}) {
    List<List<FlSpot>> lineSpots = List.generate((values[0] as List<dynamic>).length - 1, (index) => []);

    for (int i = 0; i < values.length; i++) {
      final t = DateTime.parse(values[i][0]).millisecondsSinceEpoch.toDouble();
      for (int j = 1; j < values[i].length; j++) {
        if (values[i][j] != null) lineSpots[j - 1].add(FlSpot(t, values[i][j] is int ? values[i][j].toDouble() : values[i][j]));
      }
    }
    _lines.addAll(lineSpots.where((e) => e.isNotEmpty).toList(growable: false).asMap().entries.map((e) => LineChartBarData(
          dotData: FlDotData(show: false),
          spots: e.value,
          color: _getLineColor(e.key + colorOffset),
        )));
  }

  Color _getLineColor(int i) {
    const List<Color> colors = [MyTheme.appColor, Colors.amber, Colors.redAccent, Colors.blueAccent];
    return colors[i % colors.length];
  }
}
