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
import 'package:intl/intl.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/shared/request.dart';
import 'package:stats/stats.dart';

import '../../../../shared/keyed_list.dart';
import '../../../../theme.dart';
import '../dashboard.dart';

class SmSeLineChart extends SmSeRequest {
  final List<LineChartBarData> _lines = [];
  DateFormat dateFormat = MyTheme.formatHHMM;

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
                              child: Text(dateFormat.format(dt), style: TextStyle(fontSize: MediaQuery.textScaleFactorOf(context) * 11)));
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
    final precision = calcPrecision(values);
    List<List<FlSpot>> lineSpots = List.generate((values[0] as List<dynamic>).length - 1, (index) => []);
    final List<String> timestamps = [];
    for (int i = 0; i < values.length; i++) {
      final t = DateTime.parse(values[i][0]).millisecondsSinceEpoch.toDouble();
      timestamps.add(values[i][0]);
      for (int j = 1; j < values[i].length; j++) {
        if (values[i][j] != null)
          lineSpots[j - 1].add(FlSpot(t, double.parse((values[i][j] is int ? values[i][j].toDouble() : values[i][j]).toStringAsFixed(precision))));
      }
    }
    _lines.addAll(lineSpots.where((e) => e.isNotEmpty).toList(growable: false).asMap().entries.map((e) => LineChartBarData(
          dotData: FlDotData(show: false),
          spots: e.value,
          color: getLineColor(e.key + colorOffset),
        )));
    setDateFormat(timestamps);
  }

  Color getLineColor(int i) {
    const List<Color> colors = [MyTheme.appColor, Colors.amber, Colors.redAccent, Colors.blueAccent];
    return colors[i % colors.length];
  }

  void setDateFormat(List<String> timestamps) {
    final similarities = _similarity(timestamps);
    final left = similarities.k;
    var right = similarities.t;
    if (timestamps.isEmpty) {
      dateFormat = MyTheme.formatHHMM;
    } else {
      right += timestamps[0].length - 19; // no further precision than seconds
    }
    if (right < 2) {
      if (left >= 17) {
        dateFormat = MyTheme.formatSS;
      } else {
        dateFormat = MyTheme.formatMMSS;
      }
    } else if (right <= 5) {
      if (left >= 14) {
        dateFormat = MyTheme.formatMM;
      } else {
        dateFormat = MyTheme.formatHHMM;
      }
    } else if (right <= 8) {
      if (left >= 11) {
        dateFormat = MyTheme.formatHH;
      } else {
        dateFormat = MyTheme.formatEHH;
      }
    } else {
      dateFormat = MyTheme.formatE;
    }
  }

  Pair<int, int> _similarity(List<String> timestamps) {
    if (timestamps.isEmpty) {
      return Pair(0, 0);
    }
    final l = timestamps[0].length;
    int left = l;
    int right = l;
    for (int i = 1; i < timestamps.length; i++) {
      assert(timestamps[i].length == l);
      int j = 0;
      while (j <= left && timestamps[i].codeUnitAt(j) == timestamps[0].codeUnitAt(j)) {
        j++;
      }
      left = j;

      j = 0;
      while (j <= right && timestamps[i].codeUnitAt(l - 1 - j) == timestamps[0].codeUnitAt(l - 1 - j)) {
        j++;
      }
      right = j;
    }
    return Pair(left, right);
  }

  int calcPrecision(List<dynamic> values) {
    final List<double> nums = [];
    for (int i = 0; i < values.length; i++) {
      nums.addAll((values[i] as List).skip(1).map((e) => e is int ? e.toDouble() : e));
    }
    final stats = Stats.fromData(nums);
    int precision = 0;
    if (stats.standardDeviation > 1) {
      precision = 1;
    } else {
      num std = stats.standardDeviation;
      while (std < 1) {
        std *= 10;
        precision++;
      }
    }
    return precision;
  }
}
