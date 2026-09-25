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
import 'package:mobile_app/shared/display_time.dart';

class BaseChartFormatter {
  static SideTitles getBottomTitles(BuildContext context, DateFormat dtFormat,
      {double reservedSize = 20,
      bool isUtc = true,
      double? interval,
      bool rotated = false}) {
    return SideTitles(
        showTitles: true,
        reservedSize: reservedSize,
        interval: interval,
        getTitlesWidget: (val, meta) {
          if (val == meta.max || val == meta.min) {
            return const SizedBox.shrink();
          }
          final dt = toDisplayTime(
              DateTime.fromMillisecondsSinceEpoch(val.floor(), isUtc: isUtc));
          final formatted = dtFormat.format(dt);
          if (rotated) {
            return Container(
                padding: const EdgeInsets.only(top: 3),
                child: RotatedBox(
                    quarterTurns: -1,
                    child: Text(formatted,
                        style: TextStyle(
                            fontSize:
                            MediaQuery.textScalerOf(context).scale(11)))));
          }
          return Container(
              padding: const EdgeInsets.only(top: 3),
              child: Text(formatted,
                      style: TextStyle(
                          fontSize:
                              MediaQuery.textScalerOf(context).scale(12))));
        });
  }

  static SideTitles getLeftTitles(BuildContext context,
      {double reservedSize = 30, String? suffix}) {
    return SideTitles(
        showTitles: true,
        reservedSize: reservedSize,
        getTitlesWidget: (val, meta) {
          if (val == meta.max || val == meta.min) {
            return const SizedBox.shrink();
          }
          return Text(
              suffix == null
                  ? meta.formattedValue
                  : "${meta.formattedValue} $suffix",
              style: TextStyle(
                  fontSize: MediaQuery.textScalerOf(context).scale(12)));
        });
  }

  // Icons.circle's code point (material/icons.dart) - not imported here to
  // keep this file off the full Material dependency; a Unicode bullet has no
  // fallback glyph in the bundled Roboto font, so a plain "●" tofus instead.
  static const _circleMarkerCodePoint = 0xe163;

  /// A tooltip line identifying its series by a leading coloured marker
  /// instead of colouring [text] itself, which would otherwise repeat
  /// whichever series colour fl_chart's tooltip happens to render text in -
  /// several series colours read under 3:1 against a themed tooltip fill.
  static List<TextSpan> tooltipContent(
      Color seriesColor, Color onInverseSurface, String text) {
    final style = TextStyle(
        color: onInverseSurface, fontWeight: FontWeight.bold, fontSize: 14);
    return [
      TextSpan(
          text: "${String.fromCharCode(_circleMarkerCodePoint)} ",
          style: style.copyWith(
              color: seriesColor, fontFamily: 'MaterialIcons', fontSize: 12)),
      TextSpan(text: text, style: style),
    ];
  }
}
