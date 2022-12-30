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
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:intl/intl.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/shared/request.dart';
import 'package:stats/stats.dart';

import '../../../../theme.dart';
import '../../../shared/indicator.dart';
import '../dashboard.dart';

class SmSePieChart extends SmSeRequest {
  bool preview = false;
  @override
  setPreview(bool enabled) {
    preview = enabled;
    if (enabled) {
      height = 5;
    } else {
      height = 5.0 + _active_sections.length;
    }
  }

  final List<PieChartSectionData> _sections = [];
  final List<double> nums = [];
  final List<String> titles = [];
  final List<int> _active_sections = [];
  DateFormat dateFormat = MyTheme.formatHHMM;
  int touchedIndex = -1;
  double sum = 0;
  int precision = 1;
  bool _allZero = false;
  bool showSum = false;
  String? sumUnit;

  @override
  double height = 5;

  @override
  double width = 5;

  @override
  @mustCallSuper
  Future<void> configure(dynamic data) async {
    super.configure(data);
    if (data is! Map<String, dynamic> || data["titles"] == null) return;
    titles.clear();
    (data["titles"] as List).forEach((element) => titles.add(element as String));
    if (data["showSum"] != null) {
      showSum = data["showSum"] as bool;
    }
    if (data["sumUnit"] != null) {
      sumUnit = data["sumUnit"];
    }
  }

  @override
  Widget buildInternal(BuildContext context, bool parentFlexible) {
    final Widget w = _sections.isEmpty
        ? const Center(child: Text("No Data"))
        : Container(
            height: height * heightUnit - MyTheme.insetSize,
            padding:
                const EdgeInsets.only(top: MyTheme.insetSize, right: MyTheme.insetSize, left: MyTheme.insetSize / 2, bottom: MyTheme.insetSize / 2),
            child: StatefulBuilder(builder: (context, setState) {
              _buildSections();
              final List<Widget> legendWidgets = [];
              if (_active_sections.isNotEmpty && !preview) {
                _active_sections.forEach((i) {
                  legendWidgets.addAll([
                    GestureDetector(
                        onTapDown: (_) => setState(() => touchedIndex = _active_sections.indexOf(i)),
                        onTapUp: (_) => setState(() => touchedIndex = -1),
                        onTapCancel: () => setState(() => touchedIndex = -1),
                        child: Indicator(
                          color: MyTheme.getSomeColor(i),
                          text: "${titles[i]}${_allZero ? "" : (" (${(nums[i] * 100 / sum).toStringAsFixed(1)}%)")}",
                          textColor: MyTheme.textColor!,
                          isSquare: false,
                        )),
                    const SizedBox(
                      height: 4,
                    )
                  ]);
                });
              }
              final legend = Column(mainAxisAlignment: MainAxisAlignment.end, crossAxisAlignment: CrossAxisAlignment.start, children: legendWidgets);
              return Column(children: [
                Expanded(
                    child: Stack(children: [
                  PieChart(
                    PieChartData(
                      borderData: FlBorderData(show: false),
                      pieTouchData: PieTouchData(
                        enabled: !preview,
                        touchCallback: preview
                            ? null
                            : (FlTouchEvent event, pieTouchResponse) {
                                setState(() {
                                  if (!event.isInterestedForInteractions || pieTouchResponse == null || pieTouchResponse.touchedSection == null) {
                                    touchedIndex = -1;
                                    return;
                                  }
                                  touchedIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
                                });
                              },
                      ),
                      sections: _sections,
                    ),
                    swapAnimationDuration: const Duration(milliseconds: 100),
                  ),
                  Center(
                      child: showSum
                          ? Text(
                              "${sum.toStringAsFixed(precision)}${sumUnit != null ? " $sumUnit" : ""}",
                              textScaleFactor: 2,
                            )
                          : const SizedBox.shrink())
                ])),
                const SizedBox(height: 8),
                PlatformWidget(
                  cupertino: (_, __) => Material(child: legend),
                  material: (_, __) => legend,
                )
              ]);
            }));
    return parentFlexible ? Expanded(child: w) : w;
  }

  @override
  Future<void> refreshInternal() async {
    _sections.clear();
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
    nums.clear();
    for (int i = 0; i < values.length; i++) {
      nums.addAll((values[i] as List).skip(1).map((e) => e is int ? e.toDouble() : e ?? 0));
    }
    while (nums.length > titles.length) {
      titles.add("unknown");
    }
    sum = 0;
    nums.forEach((e) => sum += e);
    if (sum == 0) {
      _allZero = true;
    } else {
      _allZero = false;
    }

    precision = calcPrecision(nums);
    _buildSections(colorOffset: colorOffset);
  }

  void _buildSections({int colorOffset = 0}) {
    _sections.clear();
    final List<int> tmpActiveSections = [];
    _sections.addAll(nums.asMap().entries.map((e) {
      bool isTouched = false;
      if (touchedIndex != -1) {
        isTouched = touchedIndex == _active_sections.indexWhere((element) => element == e.key);
      }
      final fontSize = isTouched ? 16.0 : 11.0;
      final radius = isTouched ? 60.0 : 50.0;
      final value = double.parse(e.value.toStringAsFixed(precision)) + (_allZero ? 1 : 0);
      if (value > 0) {
        tmpActiveSections.add(e.key);
      }
      return PieChartSectionData(
        title: (e.value).toStringAsFixed(precision),
        radius: radius,
        titleStyle: TextStyle(
          fontSize: fontSize,
          overflow: TextOverflow.clip,
        ),
        value: value,
        color: MyTheme.getSomeColor(e.key + colorOffset),
      );
    }).where((element) => element.value > 0));
    _active_sections.clear();
    _active_sections.addAll(tmpActiveSections);
  }

  int calcPrecision(List<double> nums) {
    final stats = Stats.fromData(nums);
    int precision = 0;
    if (stats.standardDeviation == 0) {
      if (sum == 0) {
        precision = 1;
      } else {
        double tmp = sum;
        while (tmp < 1) {
          tmp *= 10;
          precision++;
        }
      }
    } else if (stats.standardDeviation >= 1 || stats.standardDeviation == 0) {
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
