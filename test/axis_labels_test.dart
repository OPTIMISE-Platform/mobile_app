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
import 'package:mobile_app/shared/axis_labels.dart';

void main() {
  group("axisFractionDigits", () {
    test("follows the decimals of the step", () {
      expect(axisFractionDigits(0.05), 2);
      expect(axisFractionDigits(0.5), 1);
      expect(axisFractionDigits(0.002), 3);
      expect(axisFractionDigits(1), 0);
      expect(axisFractionDigits(5), 0);
      expect(axisFractionDigits(20), 0);
      expect(axisFractionDigits(0.2), 1);
      expect(axisFractionDigits(50), 0);
      expect(axisFractionDigits(1000), 0);
    });

    test("ignores floating-point noise", () {
      expect(axisFractionDigits(0.05000000001), 2);
      expect(axisFractionDigits(0.1 * 3 - 0.1), 1);
      expect(axisFractionDigits(0.1 + 0.2), isNull); // 0.3 is no fl_chart step
      expect(axisFractionDigits(0.7 - 0.2), 1);
      expect(axisFractionDigits(4.999999999), 0);
    });

    test("steps fl_chart does not round to have no digits", () {
      // Narrow axes get (max - min) / 2 unrounded.
      expect(axisFractionDigits(21.835308), isNull);
      expect(axisFractionDigits(0.3333333), isNull);
      expect(axisFractionDigits(0.0123456789), isNull);
      expect(axisFractionDigits(3.3333333), isNull);
      expect(axisFractionDigits(0.25), isNull);
      expect(axisFractionDigits(2.5), isNull);
      expect(axisFractionDigits(0.7), isNull);
    });

    test("steps below the digit cap have none", () {
      expect(axisFractionDigits(0.000001), 6);
      expect(axisFractionDigits(5e-7), isNull);
    });

    test("degenerate steps have none", () {
      expect(axisFractionDigits(0), isNull);
      expect(axisFractionDigits(-1), isNull);
      expect(axisFractionDigits(double.nan), isNull);
      expect(axisFractionDigits(double.infinity), isNull);
    });
  });

  group("formatAxisValue", () {
    TitleMeta meta(double interval,
            {double min = 19.5, double max = 20.5, String formatted = "x"}) =>
        TitleMeta(
            min: min,
            max: max,
            parentAxisSize: 400,
            axisPosition: 0,
            appliedInterval: interval,
            sideTitles: const SideTitles(),
            formattedValue: formatted,
            axisSide: AxisSide.left);

    test("ticks finer than the axis span stay distinct", () {
      // fl_chart formats a span of 1 with one digit, which reads 20.5 twice.
      final labels = [20.5, 20.45, 20.4, 20.35]
          .map((v) => formatAxisValue(v, meta(0.05)))
          .toList();
      expect(labels, ["20.50", "20.45", "20.40", "20.35"]);
      expect(labels.toSet().length, labels.length);
    });

    test("whole and half steps drop a trailing .0", () {
      expect(formatAxisValue(20, meta(0.5)), "20");
      expect(formatAxisValue(20.5, meta(0.5)), "20.5");
      expect(formatAxisValue(40, meta(20)), "40");
    });

    test("negative values that round to zero lose their sign", () {
      expect(formatAxisValue(-0.0000001, meta(0.5)), "0");
      expect(formatAxisValue(-0.0000001, meta(0.05)), "0.00");
      expect(formatAxisValue(-1.5, meta(0.5)), "-1.5");
    });

    test("tolerates a noisy applied interval", () {
      expect(formatAxisValue(0.3, meta(0.1 * 3 - 0.1)), "0.3");
      expect(formatAxisValue(20.45, meta(0.05000000001)), "20.45");
    });

    test("an unrounded step keeps fl_chart's own text", () {
      // pv_forecast on a short plot: the step is (max - min) / 2.
      expect(formatAxisValue(43.670617, meta(21.835308, formatted: "43.7")),
          "43.7");
      expect(formatAxisValue(5e-7, meta(5e-7, formatted: "0")), "0");
    });

    test("thousands keep fl_chart's abbreviated form", () {
      expect(formatAxisValue(2500, meta(500, formatted: "2.5K")), "2.5K");
    });
  });
}
