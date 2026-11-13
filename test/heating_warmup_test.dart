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

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/widgets/tabs/smart-services/heating_schedule_model.dart';
import 'package:mobile_app/widgets/tabs/smart-services/heating_warmup_model.dart';

// 2025-01-06 is a Monday, Berlin is UTC+1 in January: 04:30 local.
final _now = DateTime.utc(2025, 1, 6, 3, 30);

// Columns after the time, in the order of heatingWarmupColumns.
List<dynamic> _row({
  String zone = "zone:0",
  int? minutes,
  String? nextStart,
  double? nextTarget,
  int? nextLead,
  Object? windows,
  Object? measure,
  Object? forecast,
  double? a,
  int? episodes,
}) =>
    ["2025-01-06T03:25:00Z", zone, minutes, nextStart, nextTarget, nextLead, windows, measure, forecast, a, episodes];

HeatingWarmupRow _modelled({int? minutes, int? lead = 35, String start = "2025-01-06T05:00:00Z"}) => parseHeatingWarmupRow({
      "warmup_minutes": minutes,
      "next_start": start,
      "next_target": 21.0,
      "next_lead_minutes": lead,
      "a": 1.2,
    }, (_) {});

void main() {
  group("config", () {
    test("an instance without export id keeps the widget as it was", () {
      expect(HeatingWarmupConfig.from(null), isNull);
      expect(HeatingWarmupConfig.from(<String, dynamic>{}), isNull);
      expect(HeatingWarmupConfig.from({"warmup_export_id": ""}), isNull);
    });

    test("mode plan and show; anything else counts as show", () {
      expect(HeatingWarmupConfig.from({"warmup_export_id": "e", "warmup_mode": "plan"})!.mode, HeatingWarmupMode.plan);
      expect(HeatingWarmupConfig.from({"warmup_export_id": "e", "warmup_mode": "show"})!.mode, HeatingWarmupMode.show);
      expect(HeatingWarmupConfig.from({"warmup_export_id": "e"})!.mode, HeatingWarmupMode.show);
    });
  });

  group("zone keys", () {
    test("the key is the position in the stored plan, also when an earlier zone has no thermostat", () {
      final plan = HeatingPlan.parse(
          '{"zones":[{"name":"Gone","devices":["x"],"windows":[]},{"name":"Salon","devices":["a"],"windows":[]},{"name":"Rest","windows":[]}]}',
          17);
      final zones = plan.resolve(const [HeatingThermostat("a", "A"), HeatingThermostat("b", "B")]);
      expect([for (final z in zones) z.name], ["Salon", "Rest"]);
      expect([for (final z in zones) z.key], ["zone:1", "zone:2"]);
    });

    test("a legacy plan is zone:0", () {
      final zones = HeatingPlan.parse('{"windows":[]}', 17).resolve(const [HeatingThermostat("a", "A")]);
      expect(zones.single.key, "zone:0");
    });
  });

  group("rows", () {
    test("each zone gets its own row, a zone without one is absent", () {
      final errors = <String>[];
      final rows = heatingWarmupRows(
        ["zone:0", "zone:1", "zone:2"],
        [
          [_row(minutes: 35, a: 1.2, nextLead: 35)],
          [_row(zone: "zone:1", episodes: 2)],
          [],
        ],
        errors.add,
      );
      expect(rows.keys, ["zone:0", "zone:1"]);
      expect(rows["zone:0"]!.warmupMinutes, 35);
      expect(rows["zone:0"]!.hasModel, isTrue);
      expect(rows["zone:1"]!.hasModel, isFalse);
      expect(rows["zone:1"]!.episodes, 2);
      expect(errors, isEmpty);
    });

    test("a row of the wrong width is reported and skipped", () {
      final errors = <String>[];
      final rows = heatingWarmupRows(["zone:0"], [
        [
          [1, 2]
        ]
      ], errors.add);
      expect(rows, isEmpty);
      expect(errors, hasLength(1));
    });

    test("an unparsable JSON column is reported and the rest of the row stays", () {
      final errors = <String>[];
      final row = parseHeatingWarmupRow({
        "warmup_minutes": 12,
        "windows": "{not json",
        "measure_station": "[]",
        "forecast_station": '{"id":"X","name":"Halle","distance_km":8.1}',
      }, errors.add);
      expect(row.warmupMinutes, 12);
      expect(row.windows, isEmpty);
      expect(row.measure, isNull);
      expect(row.forecast!.name, "Halle");
      expect(errors, hasLength(2));
    });

    test("windows are read with start, target and lead; null lead stays null", () {
      final row = parseHeatingWarmupRow({
        "windows": jsonEncode([
          {"start": "2025-01-06T05:00:00Z", "target": 21, "outdoor": null, "lead_minutes": null},
          {"start": "bad", "target": 21},
        ])
      }, (_) {});
      expect(row.windows, hasLength(1));
      expect(row.windows.single.leadMinutes, isNull);
      expect(row.windows.single.target, 21);
    });
  });

  group("status", () {
    test("minutes left, almost there under a minute, unreachable at -1", () {
      expect(heatingWarmupStatus(_modelled(minutes: 35), 21), "Warming up to 21 °C, about 35 min left");
      expect(heatingWarmupStatus(_modelled(minutes: 0), 21.5), "Warming up to 21.5 °C, almost there");
      expect(heatingWarmupStatus(_modelled(minutes: -1), 21), "21 °C is not reachable at this outdoor temperature");
    });

    test("nothing without a warm-up in progress", () {
      expect(heatingWarmupStatus(_modelled(), 21), isNull);
      expect(heatingWarmupStatus(null, 21), isNull);
    });
  });

  group("next window", () {
    test("plan names the heating start", () {
      expect(heatingWarmupNextLine(_modelled(), HeatingWarmupMode.plan, _now), "Heats from 05:25 for 21 °C at 06:00");
    });

    test("plan with a start already past says it is heating", () {
      final now = DateTime.utc(2025, 1, 6, 4, 40); // 05:40 local, start was 05:25
      expect(heatingWarmupNextLine(_modelled(), HeatingWarmupMode.plan, now), "Heating for 21 °C at 06:00");
    });

    test("show only says how long it would take", () {
      expect(heatingWarmupNextLine(_modelled(), HeatingWarmupMode.show, _now), "Needs about 35 min to reach 21 °C at 06:00");
    });

    test("a window in the past, without lead or at zero lead gives no line", () {
      final late = DateTime.utc(2025, 1, 6, 5, 1);
      expect(heatingWarmupNextLine(_modelled(), HeatingWarmupMode.plan, late), isNull);
      expect(heatingWarmupNextLine(_modelled(lead: null), HeatingWarmupMode.plan, _now), isNull);
      expect(heatingWarmupNextLine(_modelled(lead: 0), HeatingWarmupMode.plan, _now), isNull);
      expect(heatingWarmupNextLine(null, HeatingWarmupMode.plan, _now), isNull);
    });

    test("a window on another day carries the weekday", () {
      final row = _modelled(start: "2025-01-07T05:00:00Z");
      expect(heatingWarmupNextLine(row, HeatingWarmupMode.show, _now), "Needs about 35 min to reach 21 °C at Tue 06:00");
    });
  });

  group("learning", () {
    test("without a model, with the count when it is known", () {
      expect(heatingWarmupLearning(null), "Learning the warm-up time");
      expect(heatingWarmupLearning(parseHeatingWarmupRow({"a": null}, (_) {})), "Learning the warm-up time");
      expect(heatingWarmupLearning(parseHeatingWarmupRow({"a": null, "episodes": 2}, (_) {})),
          "Learning the warm-up time (2 of 3 warm-ups seen)");
    });

    test("not with a model", () {
      expect(heatingWarmupLearning(_modelled()), isNull);
    });
  });

  group("stations", () {
    const leipzig = HeatingStation(name: "Leipzig", distanceKm: 12.3), halle = HeatingStation(name: "Halle", distanceKm: 8.1);

    test("both stations with name and distance", () {
      expect(heatingStationLine(leipzig, halle), "Outdoor: Leipzig (12.3 km) · Forecast: Halle (8.1 km)");
    });

    test("an own sensor, and unknown parts left out", () {
      expect(heatingStationLine(HeatingStation.ownSensor, halle), "Outdoor: own sensor · Forecast: Halle (8.1 km)");
      expect(heatingStationLine(const HeatingStation(name: "Leipzig"), const HeatingStation(distanceKm: 8)),
          "Outdoor: Leipzig · Forecast: 8.0 km");
      expect(heatingStationLine(null, halle), "Forecast: Halle (8.1 km)");
    });

    test("nothing when both are unknown", () {
      expect(heatingStationLine(null, null), isNull);
      expect(heatingStationLine(const HeatingStation(), const HeatingStation()), isNull);
    });
  });

  group("hatches", () {
    final windows = [
      HeatingWarmupWindow(DateTime.utc(2025, 1, 6, 3, 0), 19, 30), // past
      HeatingWarmupWindow(DateTime.utc(2025, 1, 6, 5, 0), 21, 35), // 05:25..06:00 local
      HeatingWarmupWindow(DateTime.utc(2025, 1, 6, 6, 0), 20, null),
    ];

    test("the future window with a lead is drawn on today's row, the past one is not", () {
      expect(heatingWarmupHatches(windows, _now, 0), [const HeatingHatch(325, 360, 21)]);
    });

    test("other weekdays of this week get nothing", () {
      expect(heatingWarmupHatches(windows, _now, 1), isEmpty);
      expect(heatingWarmupHatches(windows, _now, 6), isEmpty);
    });

    test("a phase across midnight is split over both rows and clipped", () {
      final now = DateTime.utc(2025, 1, 6, 21, 0); // 22:00 local
      final w = [HeatingWarmupWindow(DateTime.utc(2025, 1, 6, 23, 30), 21, 120)]; // 00:30 local Tue, from 22:30
      expect(heatingWarmupHatches(w, now, 0), [const HeatingHatch(1350, 1440, 21)]);
      expect(heatingWarmupHatches(w, now, 1), [const HeatingHatch(0, 30, 21)]);
    });
  });
}
