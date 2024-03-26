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
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/shared/request.dart';

import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/tabs/dashboard/dashboard.dart';

class SmSePvForecast extends SmSeRequest {
  @override
  setPreview(bool enabled) => null;

  final List<LineChartBarData> _lines = [];
  final List<VerticalLine> _verticalLines = [];
  final List<String> _recommendations = [];

  @override
  double get height => 6.0 + _recommendations.length;

  @override
  double width = 5;

  @override
  Widget buildInternal(BuildContext context, bool parentFlexible) {
    final Widget w = _lines.isEmpty
        ? const Center(child: Text("No Data"))
        : Column(children: [
          const Text("\nPV Prediction"),
          Container(
            height: 5 * heightUnit - MyTheme.insetSize,
            padding:
                const EdgeInsets.only(top: MyTheme.insetSize, right: MyTheme.insetSize, left: MyTheme.insetSize / 2, bottom: MyTheme.insetSize / 2),
            child: LineChart(
              LineChartData(
                extraLinesData: ExtraLinesData(
                  verticalLines: _verticalLines,
                ),
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
                        reservedSize: 36,
                        interval: 6 * 60 * 60 * 1000,
                        getTitlesWidget: (val, meta) {
                          if (val == meta.max || val == meta.min) {
                            return const SizedBox.shrink();
                          }
                          final dt = DateTime.fromMillisecondsSinceEpoch(val.floor()).toLocal();
                          return Container(
                              padding: const EdgeInsets.only(top: 18),
                              child: Text(MyTheme.formatHHMM.format(dt), style: TextStyle(fontSize: MediaQuery.textScaleFactorOf(context) * 11)));
                        }),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        getTitlesWidget: (val, meta) {
                          if (val == meta.max || val == meta.min) {
                            return const SizedBox.shrink();
                          }
                          return Text("${meta.formattedValue} %", style: TextStyle(fontSize: MediaQuery.textScaleFactorOf(context) * 11));
                        }),
                  ),
                ),
                lineTouchData: LineTouchData(enabled: false),
              ),
              duration: const Duration(milliseconds: 400),
            )),
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [const Text("Upcoming timeframes:   "), Text(_recommendations.join("\n"))])]);
    return parentFlexible ? Expanded(child: w) : w;
  }

  @override
  Future<void> refreshInternal() async {
    _lines.clear();
    _verticalLines.clear();
    _recommendations.clear();
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
          await _add2D(respArr[i], colorOffset: linesAdded);
          linesAdded += (respArr[i][0] as List).length - 1;
        }
      } else {
        await _add2D(respArr);
      }
    }
  }

  _add2D(List<dynamic> values, {int colorOffset = 0}) async {
    List<List<FlSpot>> lineSpots = List.generate((values[0] as List<dynamic>).length - 1, (index) => []);

    for (int i = 0; i < values.length; i++) {
      final t = DateTime.parse(values[i][0]).millisecondsSinceEpoch.toDouble();
      for (int j = 1; j < values[i].length; j++) {
        if (values[i][j] != null) {
          final y = values[i][j] is int ? values[i][j].toDouble() : values[i][j];
          lineSpots[j - 1].add(FlSpot(t, y * 100));
        }
      }
    }
    _lines.addAll(lineSpots.where((e) => e.isNotEmpty).toList(growable: false).asMap().entries.map((e) => LineChartBarData(
          dotData: FlDotData(show: false),
          spots: e.value,
          color: _getLineColor(e.key + colorOffset),
        )));
    _lines.forEach((line) async {
      double currentMax = line.spots.first.y;
      bool rising = false;
      double risingSince = double.nan;
      const double mustRiseAtLeast = 0.1;
      for (int i = line.spots.length - 1; i >= 0; i--) {
        if (line.spots[i].y > currentMax + mustRiseAtLeast) {
          currentMax = line.spots[i].y;
          if (rising == false) {
            risingSince = line.spots[i].x;
            rising = true;
          }
        } else if (rising && currentMax - line.spots[i].y > mustRiseAtLeast) {
          _recommendations.add(
              "${DateFormat.EEEE().add_H().format(DateTime.fromMillisecondsSinceEpoch(risingSince.toInt(), isUtc: true))} - ${DateFormat.H().format(DateTime.fromMillisecondsSinceEpoch(line.spots[i].x.toInt(), isUtc: true))}");
          if (currentMax > 0.5) _verticalLines.add(VerticalLine(x: (line.spots[i].x + risingSince) / 2, strokeWidth: 0, sizedPicture: await sunsvg(), color: Colors.white));
          rising = false;
        } else if (!rising) {
          currentMax = line.spots[i].y;
        }
      }
    });
  }

  Color _getLineColor(int i) {
    const List<Color> colors = [MyTheme.appColor, Colors.amber, Colors.redAccent, Colors.blueAccent];
    return colors[i % colors.length];
  }
}

Future<SizedPicture> sunsvg() async {
  final rawSvg = """
      <svg
      xmlns="http://www.w3.org/2000/svg" enable-background="new 0 0 24 24" height="24" viewBox="0 0 24 24" width="24">
      <rect fill="none" height="24" width="24"/>
      <path d="M11,4V2c0-0.55,0.45-1,1-1s1,0.45,1,1v2c0,0.55-0.45,1-1,1S11,4.55,11,4z M18.36,7.05l1.41-1.42c0.39-0.39,0.39-1.02,0-1.41 c-0.39-0.39-1.02-0.39-1.41,0l-1.41,1.42c-0.39,0.39-0.39,1.02,0,1.41C17.34,7.44,17.97,7.44,18.36,7.05z M22,11h-2 c-0.55,0-1,0.45-1,1s0.45,1,1,1h2c0.55,0,1-0.45,1-1S22.55,11,22,11z M12,19c-0.55,0-1,0.45-1,1v2c0,0.55,0.45,1,1,1s1-0.45,1-1v-2 C13,19.45,12.55,19,12,19z M5.64,7.05L4.22,5.64c-0.39-0.39-0.39-1.03,0-1.41s1.03-0.39,1.41,0l1.41,1.41 c0.39,0.39,0.39,1.03,0,1.41S6.02,7.44,5.64,7.05z M16.95,16.95c-0.39,0.39-0.39,1.03,0,1.41l1.41,1.41c0.39,0.39,1.03,0.39,1.41,0 c0.39-0.39,0.39-1.03,0-1.41l-1.41-1.41C17.98,16.56,17.34,16.56,16.95,16.95z M2,13h2c0.55,0,1-0.45,1-1s-0.45-1-1-1H2 c-0.55,0-1,0.45-1,1S1.45,13,2,13z M5.64,19.78l1.41-1.41c0.39-0.39,0.39-1.03,0-1.41s-1.03-0.39-1.41,0l-1.41,1.41 c-0.39,0.39-0.39,1.03,0,1.41C4.61,20.17,5.25,20.17,5.64,19.78z M12,6c-3.31,0-6,2.69-6,6s2.69,6,6,6s6-2.69,6-6S15.31,6,12,6z" fill='#FFFFFF'/>
    </svg>
    """
      .replaceAll("#FFFFFF", "rgb(${MyTheme.appColor.red}, ${MyTheme.appColor.green}, ${MyTheme.appColor.blue})");
  final PictureInfo pictureInfo = await vg.loadPicture(SvgStringLoader(rawSvg, theme: const SvgTheme(currentColor: MyTheme.appColor, fontSize: 8)), null);
  final sizedPicture = SizedPicture(pictureInfo.picture, 24, 24);
  return sizedPicture;
}
