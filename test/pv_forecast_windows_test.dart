/*
 * Copyright 2026 InfAI (CC SES)
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
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mobile_app/shared/display_time.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/pv_forecast.dart';

// The widget scales the fractions it receives by 100 before scanning.
List<FlSpot> hourly(List<double> fractions, {DateTime? start}) {
  final t0 = start ?? DateTime.utc(2026, 1, 1);
  return [
    for (var i = 0; i < fractions.length; i++)
      FlSpot(t0.add(Duration(hours: i)).millisecondsSinceEpoch.toDouble(),
          fractions[i] * 100),
  ];
}

// The golden fixture: zero overnight, peak at noon.
const day = [
  0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.05, 0.15, 0.35, 0.55, 0.75, 0.9, //
  0.9, 0.75, 0.55, 0.35, 0.15, 0.05, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
];

void main() {
  setUp(() {
    useUtcForDisplayTime = true;
  });

  tearDown(() {
    useUtcForDisplayTime = false;
  });

  group("findForecastWindows", () {
    test("finds the day's window with the earlier time as from", () {
      final spots = hourly(day);
      final windows = findForecastWindows(spots);
      expect(windows.length, 1);
      expect(windows.single.from, spots[10].x);
      expect(windows.single.to, spots[17].x);
      expect(windows.single.from, lessThan(windows.single.to));
      expect(windows.single.peak, closeTo(90, 1e-9));
      expect(windows.single.middle, (spots[10].x + spots[17].x) / 2);
    });

    test("returns several windows in chronological order", () {
      final spots = hourly([...day, ...day]);
      final windows = findForecastWindows(spots);
      expect(windows.length, 2);
      expect(windows[0].from, spots[10].x);
      expect(windows[0].to, spots[17].x);
      expect(windows[1].from, spots[34].x);
      expect(windows[1].to, spots[41].x);
    });

    test("a line that ends on a climb has no window at its end", () {
      // Scanning back from the last point, that point is the baseline; it
      // must not count as a climb just because the first point is lower.
      expect(findForecastWindows(hourly([0.0, 0.0, 0.05, 0.15, 0.35, 0.55])),
          isEmpty);
    });

    test("a flat or empty line has none", () {
      expect(findForecastWindows(hourly(List.filled(8, 0.4))), isEmpty);
      expect(findForecastWindows(const []), isEmpty);
    });
  });

  group("formatForecastWindow", () {
    test("names the weekday of the start, then the end hour", () {
      final spots = hourly(day);
      expect(formatForecastWindow(findForecastWindows(spots).single),
          "Thursday 10 - 17");
    });

    test("keeps the order across midnight", () {
      final w = ForecastWindow(
          DateTime.utc(2026, 1, 1, 22).millisecondsSinceEpoch.toDouble(),
          DateTime.utc(2026, 1, 2, 3).millisecondsSinceEpoch.toDouble(),
          80);
      expect(formatForecastWindow(w), "Thursday 22 - 03");
    });

    test("renders in the display time zone", () {
      useUtcForDisplayTime = false;
      final from = DateTime.utc(2026, 1, 1, 10);
      final to = DateTime.utc(2026, 1, 1, 17);
      final w = ForecastWindow(from.millisecondsSinceEpoch.toDouble(),
          to.millisecondsSinceEpoch.toDouble(), 80);
      // Same formatter as the code under test: it pads the hour ("05").
      final hour = DateFormat.H();
      expect(formatForecastWindow(w).endsWith(" - ${hour.format(to.toLocal())}"),
          isTrue);
      expect(
          formatForecastWindow(w)
              .contains(" ${hour.format(from.toLocal())} - "),
          isTrue);
    });
  });
}
