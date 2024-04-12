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
import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_app/models/db_query.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/shared/chart.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/shared/request.dart';
import 'package:mutex/mutex.dart';
import 'package:stats/stats.dart';

import 'package:mobile_app/shared/keyed_list.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/tabs/dashboard/dashboard.dart';

class SmSeLineChart extends SmSeRequest {
  bool preview = false;

  @override
  setPreview(bool enabled) => preview = enabled;

  final List<LineChartBarData> _lines = [];
  DateFormat dateFormat = MyTheme.formatHHMM;
  final List<String> titles = [];

  @override
  double height = 5;

  @override
  double width = 5;

  bool usesTSWrapperRequest = false;
  List<DbQuery>? queries;
  int left = double.maxFinite.toInt();
  int right = (0.0 - double.maxFinite).toInt();
  final List<String> timestamps = [];
  final List<int> rawTimestamps = [];
  Duration? initialTimestampDifference;
  Mutex loadMoreData = Mutex();

  @override
  @mustCallSuper
  Future<void> configure(dynamic data) async {
    super.configure(data);
    if (data is! Map<String, dynamic> || data["titles"] == null) return;
    titles.clear();
    (data["titles"] as List)
        .forEach((element) => titles.add(element as String));
    usesTSWrapperRequest =
        data["uses_ts_wrapper_request"] ?? usesTSWrapperRequest;
    if (usesTSWrapperRequest) {
      final l = json.decode(request.body) as List<dynamic>;
      queries = List.generate(l.length, (index) => DbQuery.fromJson(l[index]));
    }
  }

  @override
  Widget buildInternal(BuildContext context, bool parentFlexible) {

    final Widget w = _lines.isEmpty
        ? const Center(child: Text("No Data"))
        : Container(
            height: height * heightUnit - MyTheme.insetSize,
            //width: MediaQuery.of(context).size.width,
            padding: const EdgeInsets.only(
                top: MyTheme.insetSize,
                right: MyTheme.insetSize,
                left: MyTheme.insetSize / 2,
                bottom: MyTheme.insetSize / 2),
            child: gestureDetector(
                context,
                LineChart(
                  LineChartData(
                    borderData: FlBorderData(show: false),
                    lineBarsData: _lines,
                    maxX: right.toDouble(),
                    minX: left.toDouble(),
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
                        sideTitles: BaseChartFormatter.getBottomTitles(context, dateFormat),
                      ),
                      leftTitles: AxisTitles(
                        sideTitles: BaseChartFormatter.getLeftTitles(context),
                      ),
                    ),
                    lineTouchData: LineTouchData(
                        enabled: !preview,
                        touchTooltipData: LineTouchTooltipData(
                            fitInsideVertically: true,
                            fitInsideHorizontally: true,
                            getTooltipItems: (spots) => spots
                                .map((e) => LineTooltipItem(
                                    "${e.barIndex < titles.length ? "${titles[e.barIndex]}\n" : ""}${e.y}",
                                    TextStyle(
                                        color:
                                            MyTheme.getSomeColor(e.barIndex))))
                                .toList())),
                  ),
                  duration: Duration.zero,
                )));
    return parentFlexible ? Expanded(child: w) : w;
  }

  @override
  Future<void> refreshInternal() async {
    _lines.clear();
    rawTimestamps.clear();
    timestamps.clear();
    await addFromRequest(request);
  }

  void add2D(List<dynamic> values, {int colorOffset = 0}) {
    final precision = calcPrecision(values);
    List<List<FlSpot>> lineSpots =
        List.generate((values[0] as List<dynamic>).length - 1, (index) => []);
    for (int i = 0; i < values.length; i++) {
      final t = DateTime.parse(values[i][0]);
      for (int j = 1; j < values[i].length; j++) {
        if (values[i][j] != null) {
          rawTimestamps.add(t.millisecondsSinceEpoch);
          timestamps.add(t.toIso8601String());
          lineSpots[j - 1].add(FlSpot(
              t.millisecondsSinceEpoch.toDouble(),
              double.parse(
                  (values[i][j] is int ? values[i][j].toDouble() : values[i][j])
                      .toStringAsFixed(precision))));
        }
      }
    }
    lineSpots
        .where((e) => e.isNotEmpty)
        .toList(growable: false)
        .asMap()
        .entries
        .forEach((e) {
      if (e.key < _lines.length) {
        _lines[e.key].spots.addAll(e.value);
        _lines[e.key].spots.sort((a, b) {
          final d = a.x - b.x;
          return d < 0 ? d.floor() : d.ceil();
        });
        _lines[e.key] = LineChartBarData(
          dotData: const FlDotData(show: false),
          spots: _lines[e.key].spots,
          color: MyTheme.getSomeColor(e.key + colorOffset),
        );
      } else {
        _lines.add(LineChartBarData(
          dotData: const FlDotData(show: false),
          spots: e.value,
          color: MyTheme.getSomeColor(e.key + colorOffset),
        ));
      }
    });
    rawTimestamps.sort();
    setDateFormat(timestamps, rawTimestamps);
  }

  void setDateFormat(List<String> timestamps, List<int> rawTimestamps) {
    if (rawTimestamps.length == 1) {
      dateFormat = MyTheme.formatEddMMy;
      return;
    }
    for (int i = 1; i < rawTimestamps.length; i++) {
      if (rawTimestamps[i] - rawTimestamps[i - 1] != 604800000) {
        //exactly one week apart
        break;
      }
      if (i == timestamps.length - 1) {
        dateFormat = MyTheme.formatDDMM;
        return;
      }
    }
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
    } else if (right == 14) {
      dateFormat = MyTheme.formatMMM;
    } else if (right == 17) {
      dateFormat = MyTheme.formatY;
    } else {
      dateFormat = MyTheme.formatE;
    }
  }

  Pair<int, int> _similarity(List<String> timestamps) {
    if (timestamps.isEmpty || timestamps.length == 1) {
      return Pair(0, 0);
    }
    final l = timestamps[0].length;
    int left = l;
    int right = l;
    for (int i = 1; i < timestamps.length; i++) {
      assert(timestamps[i].length == l);
      int j = 0;
      while (j <= left &&
          timestamps[i].codeUnitAt(j) == timestamps[0].codeUnitAt(j) &&
          j < timestamps[i].length - 1) {
        j++;
      }
      left = j;

      j = 0;
      while (j <= right &&
          timestamps[i].codeUnitAt(l - 1 - j) ==
              timestamps[0].codeUnitAt(l - 1 - j) &&
          j < timestamps[i].length - 1) {
        j++;
      }
      right = j;
    }
    return Pair(left, right);
  }

  int calcPrecision(List<dynamic> values) {
    final List<double> nums = [];
    for (int i = 0; i < values.length; i++) {
      nums.addAll((values[i] as List)
          .skip(1)
          .map((e) => e is int ? e.toDouble() : e ?? 0));
    }
    final stats = Stats.fromData(nums);
    int precision = 0;
    if (stats.standardDeviation > 1) {
      precision = 1;
    } else {
      num std = stats.standardDeviation;
      while (std < 1 && std != 0) {
        std *= 10;
        precision++;
      }
    }
    return precision;
  }

  Future<void> addData(bool toRight) async {
    final diff = (initialTimestampDifference ?? Duration.zero).inMilliseconds;
    List<DbQuery> newBody = List.generate(queries?.length ?? 0, (i) {
      final e = DbQuery.from(queries![i]);
      if (toRight) {
        e.time = QueriesRequestElementTime(
            null,
            DateTime.fromMillisecondsSinceEpoch(rawTimestamps.last, isUtc: true)
                .toIso8601String(),
            DateTime.fromMillisecondsSinceEpoch(rawTimestamps.length + diff,
                    isUtc: true)
                .toIso8601String());
      } else {
        e.time = QueriesRequestElementTime(
            null,
            DateTime.fromMillisecondsSinceEpoch(rawTimestamps.first - diff,
                    isUtc: true)
                .toIso8601String(),
            DateTime.fromMillisecondsSinceEpoch(rawTimestamps.first,
                    isUtc: true)
                .toIso8601String());
      }

      return e;
    });
    final newRequest = Request.from(request);
    newRequest.body = json.encode(newBody);
    await addFromRequest(newRequest);
  }

  Future<void> addFromRequest(Request request) async {
    final resp = await request.perform<List<dynamic>>();
    if (resp.statusCode == null || resp.statusCode! > 299 || resp.data == null) {
      return;
    } else {
      final respArr = resp.data!;
      if (respArr.isEmpty) return;
      if (respArr[0] is! List || respArr[0].isEmpty) return;
      if (respArr[0][0] is List) {
        int linesAdded = 0;
        for (int i = 0; i < respArr.length; i++) {
          if (respArr[i].isEmpty) continue;
          add2D(respArr[i], colorOffset: linesAdded);
          linesAdded += (respArr[i][0] as List).length - 1;
        }
      } else {
        add2D(respArr);
      }
    }
    if (initialTimestampDifference == null && rawTimestamps.isNotEmpty) {
      initialTimestampDifference =
          DateTime.fromMillisecondsSinceEpoch(rawTimestamps.last, isUtc: true)
              .difference(DateTime.fromMillisecondsSinceEpoch(
                  rawTimestamps.first,
                  isUtc: true));
      left = min(left, rawTimestamps.first);
      right = max(right, rawTimestamps.last);
    }
  }

  Widget gestureDetector(BuildContext context, Widget child) {
    return GestureDetector(
        onHorizontalDragUpdate: preview || !usesTSWrapperRequest
            ? null
            : (details) async {
                if (loadMoreData.isLocked) return;
                await loadMoreData.acquire();
                final swipeWidth = max(
                        ((initialTimestampDifference ?? Duration.zero)
                                .inMilliseconds *
                            (details.delta.distance /
                                MediaQuery.of(context).size.width)),
                        0)
                    .toInt();
                if (details.delta.direction > 0) {
                  // right
                  left += swipeWidth;
                  right += swipeWidth;
                  if (right > rawTimestamps.last) {
                    await addData(true);
                  }
                } else {
                  // left
                  left -= swipeWidth;
                  right -= swipeWidth;
                  if (left < rawTimestamps.first) {
                    await addData(false);
                  }
                }
                redrawDashboard(context);
                loadMoreData.release();
              },
        child: child);
  }
}
