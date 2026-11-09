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

String _windows = '{"weekdays":[0,1,2,3,4],"from":"06:00","to":"20:00","temperature":20}';

String _opt(String id, String label) =>
    json.encode({"device_selection": {"device_id": "urn:infai:ses:device:$id", "service_id": null, "path": null}, "label": label});

// The vectors were computed by the process script of the smart service; the model has to resolve
// the zones exactly as it does.
void main() {
  final vectors = (json.decode(File("test/fixtures/heating_zone_vectors.json").readAsStringSync()) as Map<String, dynamic>)["cases"] as List;

  group("zone vectors", () {
    for (final v in vectors.cast<Map<String, dynamic>>()) {
      test(v["name"], () {
        List<HeatingZone> resolve() =>
            HeatingPlan.parse(v["schedule"], v["setback"]).resolve(parseHeatingThermostats(v["thermostats"]));
        if (!v.containsKey("zones")) {
          expect(resolve, throwsA(isA<HeatingScheduleException>()));
          return;
        }
        final labels = {for (final t in parseHeatingThermostats(v["thermostats"])) t.id: t.label};
        final got = resolve();
        final want = (v["zones"] as List).cast<Map<String, dynamic>>();
        expect(got.length, want.length);
        for (final (i, z) in got.indexed) {
          expect(z.name, want[i]["name"]);
          expect(z.thermostats.map((t) => t.id), want[i]["devices"]);
          expect(z.thermostats.map((t) => t.label), [for (final d in want[i]["devices"]) labels[d]]);
          expect(z.schedule.setback, (want[i]["setback"] as num).toDouble());
          expect(z.schedule.serialise(), HeatingSchedule.parse(json.encode({"windows": want[i]["windows"]}), 0).serialise());
        }
      });
    }

    test("a plan survives parse, serialise, parse for every valid case", () {
      for (final v in vectors.cast<Map<String, dynamic>>().where((v) => v.containsKey("zones"))) {
        final first = HeatingPlan.parse(v["schedule"], v["setback"]);
        final text = first.serialise();
        final second = HeatingPlan.parse(text, v["setback"]);
        expect(second.serialise(), text);
        final selected = parseHeatingThermostats(v["thermostats"]);
        String summary(HeatingPlan p) => json.encode([
              for (final z in p.resolve(selected)) [z.name, z.thermostats.map((t) => t.id).toList(), z.schedule.serialise(), z.schedule.setback]
            ]);
        expect(summary(second), summary(first));
      }
    });
  });

  group("serialise", () {
    test("one rest zone without own setback writes the legacy shape", () {
      final legacy = '{"windows":[$_windows]}';
      expect(HeatingPlan.parse(legacy, 17).serialise(), legacy);
      expect(HeatingPlan.parse('{"zones":[{"name":"Alle","windows":[$_windows]}]}', 17).serialise(), legacy);
      expect(const HeatingPlan([HeatingZoneDef(" ", null, [HeatingWindow([0], 360, 480, 20)], null)], 17).serialise(),
          '{"windows":[{"weekdays":[0],"from":"06:00","to":"08:00","temperature":20}]}');
      // any other name is kept, which the legacy shape cannot do
      expect(HeatingPlan.parse('{"zones":[{"name":"Haus","windows":[$_windows]}]}', 17).serialise(),
          '{"zones":[{"name":"Haus","windows":[{"weekdays":[0,1,2,3,4],"from":"06:00","to":"20:00","temperature":20}]}]}');
      expect(HeatingPlan.parse(legacy, 17).legacy, isTrue);
    });

    test("anything else writes zones, with devices only for named zones and setback only when own", () {
      final plan = HeatingPlan.parse(
          '{"zones":[{"name":"Bad","devices":["urn:infai:ses:device:bbb"],"windows":[$_windows],"setback":19.5},{"windows":[]}]}', 17);
      expect(
          plan.serialise(),
          '{"zones":[{"name":"Bad","devices":["urn:infai:ses:device:bbb"],"windows":[{"weekdays":[0,1,2,3,4],"from":"06:00","to":"20:00","temperature":20}],"setback":19.5},'
          '{"name":"Zone 2","windows":[]}]}');
      // a single zone with devices, or a rest zone with an own setback, is not the legacy shape
      expect(HeatingPlan.parse('{"zones":[{"devices":["urn:infai:ses:device:aaa"],"windows":[]}]}', 17).serialise(),
          '{"zones":[{"name":"Zone 1","devices":["urn:infai:ses:device:aaa"],"windows":[]}]}');
      expect(HeatingPlan.parse('{"zones":[{"name":"Alle","windows":[],"setback":18}]}', 17).serialise(),
          '{"zones":[{"name":"Alle","windows":[],"setback":18}]}');
    });
  });

  group("what the script accepts", () {
    test("temperature and zone setback may be numeric strings", () {
      final plan = HeatingPlan.parse(
          '{"zones":[{"name":"A","windows":[{"from":"06:00","to":"08:00","temperature":" 21.5 "}],"setback":"19"}]}', 17);
      expect(plan.zones.single.windows.single.temperature, 21.5);
      expect(plan.zones.single.setback, 19);
      for (final bad in ['""', 'true', '[1]', '"x"', '"Infinity"']) {
        expect(() => HeatingPlan.parse('{"windows":[{"from":"06:00","to":"08:00","temperature":$bad}]}', 17),
            throwsA(isA<HeatingScheduleException>()), reason: bad);
      }
    });

    test("devices that are not text are ignored by the resolution and written back unchanged", () {
      const text = '{"zones":[{"name":"A","devices":[5,"urn:infai:ses:device:aaa",null],"windows":[]}]}';
      final plan = HeatingPlan.parse(text, 17);
      expect(plan.resolve(parseHeatingThermostats([_opt("aaa", "A")])).single.thermostats.map((t) => t.id), ["urn:infai:ses:device:aaa"]);
      expect(plan.serialise(), text);
    });
  });

  group("thermostats", () {
    test("options may be JSON texts or maps, the value a list or the text of one; a device counts once", () {
      final text = json.encode([_opt("aaa", "A"), _opt("aaa", "again"), json.decode(_opt("bbb", "B")), "{}", json.encode({"label": "x"})]);
      for (final value in [text, json.decode(text)]) {
        expect(parseHeatingThermostats(value).map((t) => (t.id, t.label)),
            [("urn:infai:ses:device:aaa", "A"), ("urn:infai:ses:device:bbb", "B")]);
      }
      expect(parseHeatingThermostats(null), isEmpty);
      expect(parseHeatingThermostats(""), isEmpty);
      expect(() => parseHeatingThermostats("{}"), throwsA(isA<HeatingScheduleException>()));
    });
  });

  test("a bad zone names itself in the message", () {
    expect(() => HeatingPlan.parse('{"zones":[{"name":"Bad","windows":[{"from":"x","to":"1:00","temperature":1}]}]}', 17),
        throwsA(predicate((e) => e.toString().startsWith("Bad: "))));
  });
}
