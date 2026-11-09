/*
 * Copyright (c) 2026 InfAI (CC SES)
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
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/widgets/tabs/smart-services/heating_schedule_model.dart';

// The vectors were computed by the process script of the smart service; the
// model has to reproduce every one of them.
void main() {
  final vectors = json.decode(File("test/fixtures/heating_schedule_vectors.json").readAsStringSync()) as Map<String, dynamic>;

  group("vectors", () {
    for (final (i, v) in (vectors["valid"] as List).cast<Map<String, dynamic>>().indexed) {
      test("valid $i: ${v["plan"]} at ${v["now"]}", () {
        final schedule = HeatingSchedule.parse(v["schedule"], v["setback"]);
        final now = DateTime.parse(v["now"]);
        expect(schedule.target(now), (v["temperature"] as num).toDouble());

        final next = schedule.nextSwitch(now);
        final nextAt = DateTime.parse(v["next_at"]);
        final constant = nextAt == now.add(const Duration(days: 7)) && v["next_temperature"] == v["temperature"];
        if (constant) {
          expect(next, isNull);
        } else {
          expect(next, isNotNull);
          expect(next!.at, nextAt);
          expect(next.temperature, (v["next_temperature"] as num).toDouble());
        }
      });
    }

    for (final (i, v) in (vectors["invalid"] as List).cast<Map<String, dynamic>>().indexed) {
      test("invalid $i: ${v["error"]}", () {
        expect(() => HeatingSchedule.parse(v["schedule"], v["setback"]), throwsA(isA<HeatingScheduleException>()));
      });
    }
  });

  test("a plan survives parse, serialise, parse", () {
    for (final v in (vectors["valid"] as List).cast<Map<String, dynamic>>()) {
      final first = HeatingSchedule.parse(v["schedule"], v["setback"]);
      final text = first.serialise();
      final second = HeatingSchedule.parse(text, v["setback"]);
      expect(second.serialise(), text);
      final now = DateTime.parse(v["now"]);
      expect(second.target(now), first.target(now));
      expect(second.nextSwitch(now)?.at, first.nextSwitch(now)?.at);
    }
  });

  test("serialising writes exactly the four keys and integral temperatures without a fraction", () {
    final s = HeatingSchedule.parse('{"windows":[{"from":"6:00","to":"24:00","temperature":20.0,"extra":1},{"weekdays":[5],"from":"08:00","to":"09:30","temperature":21.5}]}', 17);
    expect(
        s.serialise(),
        '{"windows":[{"weekdays":[0,1,2,3,4,5,6],"from":"06:00","to":"24:00","temperature":20},'
        '{"weekdays":[5],"from":"08:00","to":"09:30","temperature":21.5}]}');
  });

  group("segments", () {
    test("a window past midnight ends on the day after its weekday", () {
      final s = HeatingSchedule.parse('{"windows":[{"weekdays":[4],"from":"22:00","to":"02:00","temperature":19}]}', 16);
      List<(int, int, double, bool)> on(int d) => [for (final g in s.segmentsOf(d)) (g.from, g.to, g.temperature, g.planned)];
      expect(on(4), [(0, 1320, 16.0, false), (1320, 1440, 19.0, true)]);
      expect(on(5), [(0, 120, 19.0, true), (120, 1440, 16.0, false)]);
      expect(on(6), [(0, 1440, 16.0, false)]);
    });

    test("the last day of the week hands a window over to Monday", () {
      final s = HeatingSchedule.parse('{"windows":[{"weekdays":[6],"from":"23:00","to":"01:00","temperature":19}]}', 16);
      expect(s.segmentsOf(0).first.temperature, 19);
      expect(s.segmentsOf(0).first.to, 60);
    });

    test("overlapping windows show the higher temperature and equal neighbours merge", () {
      final s = HeatingSchedule.parse(
          '{"windows":[{"from":"06:00","to":"12:00","temperature":20},{"from":"12:00","to":"18:00","temperature":20},{"weekdays":[0],"from":"07:00","to":"09:00","temperature":22}]}',
          17);
      expect([for (final g in s.segmentsOf(0)) (g.from, g.temperature)], [(0, 17.0), (360, 20.0), (420, 22.0), (540, 20.0), (1080, 17.0)]);
      expect([for (final g in s.segmentsOf(1)) (g.from, g.to)], [(0, 360), (360, 1080), (1080, 1440)]);
    });
  });
}
