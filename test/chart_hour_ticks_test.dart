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

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/shared/display_time.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/line_chart.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/shared/chart.dart';

const _hour = Duration.millisecondsPerHour;

void main() {
  tearDown(() {
    useUtcForDisplayTime = false;
  });

  group("hourLabelStep", () {
    test("takes the smallest step that fits the label budget", () {
      // 360px hold 9 labels at 40px each.
      expect(BaseChartFormatter.hourLabelStep(6 * _hour, 360), 1);
      expect(BaseChartFormatter.hourLabelStep(9 * _hour, 360), 1);
      expect(BaseChartFormatter.hourLabelStep(18 * _hour, 360), 2);
      expect(BaseChartFormatter.hourLabelStep(23 * _hour, 360), 3);
      expect(BaseChartFormatter.hourLabelStep(48 * _hour, 360), 6);
      expect(BaseChartFormatter.hourLabelStep(96 * _hour, 360), 12);
      expect(BaseChartFormatter.hourLabelStep(7 * 24 * _hour, 360), 24);
    });

    test("switches exactly where the label count passes the budget", () {
      // 8 labels of 3h just fit into 24h, one more millisecond needs a 9th.
      expect(BaseChartFormatter.hourLabelStep(24 * _hour, 320), 3);
      expect(BaseChartFormatter.hourLabelStep(24 * _hour + 1, 320), 6);
    });

    test("width counts in whole 40px slots", () {
      expect(BaseChartFormatter.hourLabelStep(24 * _hour, 319.9), 6);
      expect(BaseChartFormatter.hourLabelStep(24 * _hour, 320), 3);
    });

    test("a narrow or negative plot still allows one label", () {
      expect(BaseChartFormatter.hourLabelStep(_hour, 0), 1);
      expect(BaseChartFormatter.hourLabelStep(2 * _hour, -50), 2);
    });

    test("gives none when even the day step piles labels up", () {
      // 30 days at 24h are 30 labels in a budget of 9.
      expect(BaseChartFormatter.hourLabelStep(30 * 24 * _hour, 360), isNull);
      expect(BaseChartFormatter.hourLabelStep(60 * 24 * _hour, 120), isNull);
    });

    test("the day step still fits where its labels do", () {
      expect(BaseChartFormatter.hourLabelStep(9 * 24 * _hour, 360), 24);
      expect(BaseChartFormatter.hourLabelStep(9 * 24 * _hour + 1, 360), isNull);
    });

    test("only offers steps that divide a day", () {
      for (final step in BaseChartFormatter.hourSteps) {
        expect(24 % step, 0);
      }
    });
  });

  group("hourTickBaseline", () {
    test("is the display-time midnight of the day", () {
      useUtcForDisplayTime = true;
      final ms = DateTime.utc(2026, 1, 1, 13, 45).millisecondsSinceEpoch;
      expect(BaseChartFormatter.hourTickBaseline(ms),
          DateTime.utc(2026, 1, 1).millisecondsSinceEpoch.toDouble());
    });

    test("a midnight maps to itself", () {
      useUtcForDisplayTime = true;
      final ms = DateTime.utc(2026, 3, 8).millisecondsSinceEpoch;
      expect(BaseChartFormatter.hourTickBaseline(ms), ms.toDouble());
    });

    test("follows the local zone outside tests' UTC switch", () {
      final t = DateTime.utc(2026, 6, 1, 13, 45);
      final l = t.toLocal();
      expect(BaseChartFormatter.hourTickBaseline(t.millisecondsSinceEpoch),
          DateTime(l.year, l.month, l.day).millisecondsSinceEpoch.toDouble());
    });

    test("every step from the baseline lands on a whole hour", () {
      useUtcForDisplayTime = true;
      final baseline = BaseChartFormatter.hourTickBaseline(
          DateTime.utc(2026, 1, 1, 13, 45).millisecondsSinceEpoch);
      for (final step in BaseChartFormatter.hourSteps) {
        for (var k = -5; k <= 30; k++) {
          final t = DateTime.fromMillisecondsSinceEpoch(
              (baseline + k * step * _hour).round(),
              isUtc: true);
          expect(t.minute, 0);
          expect(t.second, 0);
          expect(t.hour % step, 0, reason: "step $step, k $k");
        }
      }
    });
  });

  group("SmSeLineChart.hourStepMs", () {
    SmSeLineChart hourly() => SmSeLineChart()
      ..hourlyLabels = true
      ..left = 0
      ..right = 23 * _hour;

    test("gives the step for a finite width", () {
      expect(hourly().hourStepMs(360 + 30), 3 * _hour);
    });

    test("leaves the interval to fl_chart for an unbounded width", () {
      expect(hourly().hourStepMs(double.infinity), isNull);
      expect(hourly().hourStepMs(double.nan), isNull);
    });

    test("leaves it to fl_chart when the labels are not whole hours", () {
      expect(hourly().hourStepMs(390), isNotNull);
      expect((hourly()..hourlyLabels = false).hourStepMs(390), isNull);
    });
  });
}
