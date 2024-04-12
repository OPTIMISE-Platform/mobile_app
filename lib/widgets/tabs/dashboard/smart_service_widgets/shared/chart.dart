/*
 * Copyright 2024 InfAI (CC SES)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

class BaseChartFormatter {

  static SideTitles getBottomTitles(BuildContext context, DateFormat dtFormat, {double reservedSize = 20, bool isUtc = true, double? interval, }) {
    return SideTitles(
        showTitles: true,
        reservedSize: reservedSize,
        interval: interval,
        getTitlesWidget: (val, meta) {
          if (val == meta.max || val == meta.min) {
            return const SizedBox.shrink();
          }
          final dt =
              DateTime.fromMillisecondsSinceEpoch(val.floor(), isUtc: isUtc)
                  .toLocal();
          debugPrint(dt.toString());
          final formatted = dtFormat.format(dt);
          debugPrint(formatted);
          return Container(
              padding: const EdgeInsets.only(top: 3),
              child: Text(formatted,
                  style: TextStyle(
                      fontSize: MediaQuery.textScalerOf(context).scale(12))));
        });
  }

  static SideTitles getLeftTitles(BuildContext context, {double reservedSize = 30, String? suffix}) {
    return SideTitles(
        showTitles: true,
        reservedSize: reservedSize,
        getTitlesWidget: (val, meta) {
          if (val == meta.max || val == meta.min) {
            return const SizedBox.shrink();
          }
          return Text(suffix == null ? meta.formattedValue : "${meta.formattedValue} $suffix",
              style: TextStyle(
                  fontSize: MediaQuery.textScalerOf(context).scale(12)));
        });
  }
}
