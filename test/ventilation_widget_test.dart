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

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/ventilation.dart';

Map<String, dynamic> fourRooms() => {
      "outdoor": {"t": 8.1, "rh": 90.0, "valid": true},
      "rooms": [
        {"name": "Schlafzimmer", "state": "helps", "t": 21.3, "rh": 74.2, "rh_after": 55.1},
        {"name": "Bad", "state": "helps", "t": 22.0, "rh": 68.0, "rh_after": 61.0},
        {"name": "Wohnzimmer", "state": "no_benefit", "t": 21.0, "rh": 52.0, "rh_after": 49.0},
        {"name": "Keller", "state": "missing"},
      ],
      "threshold": 60,
    };

void main() {
  group("envelope", () {
    test("reads value, updated_at, outdoor, rooms and threshold", () {
      final s = VentilationState.fromJson({
        "key": "dep-1_ventilation_state",
        "deployment_id": "dep-1",
        "updated_at": "2026-10-23T07:59:12.123Z",
        "value": fourRooms(),
      })!;
      expect(s.updatedAt, DateTime.utc(2026, 10, 23, 7, 59, 12, 123));
      expect(s.outdoor!.valid, isTrue);
      expect(s.outdoor!.t, 8.1);
      expect(s.outdoor!.rh, 90.0);
      expect(s.threshold, 60.0);
      expect(s.rooms.map((r) => r.name), ["Schlafzimmer", "Bad", "Wohnzimmer", "Keller"]);
      expect(s.rooms[0].state, VentilationRoomState.helps);
      expect(s.rooms[0].rh, 74.2);
      expect(s.rooms[0].rhAfter, 55.1);
      expect(s.rooms[2].state, VentilationRoomState.noBenefit);
      expect(s.rooms[3].state, VentilationRoomState.missing);
      expect(s.rooms[3].rh, isNull);
      expect(s.rooms[3].rhAfter, isNull);
    });

    test("an envelope without updated_at has no updatedAt", () {
      final s = VentilationState.fromJson({"value": fourRooms()})!;
      expect(s.updatedAt, isNull);
      expect(s.rooms, hasLength(4));
    });

    test("an envelope with an unparsable updated_at has no updatedAt", () {
      final s = VentilationState.fromJson({"updated_at": "gestern", "value": fourRooms()})!;
      expect(s.updatedAt, isNull);
    });
  });

  group("bare state object", () {
    test("parses the same fields without an envelope", () {
      final s = VentilationState.fromJson(fourRooms())!;
      expect(s.updatedAt, isNull);
      expect(s.rooms, hasLength(4));
      expect(s.rooms[1].rhAfter, 61.0);
      expect(s.threshold, 60.0);
    });

    test("a bare object with updated_at beside outdoor and rooms is not an envelope", () {
      final s = VentilationState.fromJson({"updated_at": "2026-10-23T07:59:12Z", ...fourRooms()})!;
      expect(s.updatedAt, isNull);
      expect(s.rooms, hasLength(4));
    });
  });

  group("unusable bodies", () {
    test("non-map bodies give null", () {
      expect(VentilationState.fromJson(null), isNull);
      expect(VentilationState.fromJson("not json"), isNull);
      expect(VentilationState.fromJson(42), isNull);
      expect(VentilationState.fromJson([fourRooms()]), isNull);
    });

    test("a map with neither outdoor nor rooms gives null", () {
      expect(VentilationState.fromJson({"threshold": 60}), isNull);
      expect(VentilationState.fromJson({"value": {"threshold": 60}}), isNull);
      expect(VentilationState.fromJson({"value": "text"}), isNull);
    });

    test("an envelope whose value is not a map is read as a bare object without rooms, so null", () {
      expect(VentilationState.fromJson({"value": 3, "updated_at": "2026-10-23T07:59:12Z"}), isNull);
    });
  });

  group("missing fields", () {
    test("rooms absent: outdoor only, no rooms", () {
      final s = VentilationState.fromJson({"outdoor": {"t": 8.1, "rh": 90.0, "valid": true}})!;
      expect(s.rooms, isEmpty);
      expect(s.outdoor!.valid, isTrue);
      expect(s.threshold, isNull);
    });

    test("rooms empty: outdoor only, no rooms", () {
      final s = VentilationState.fromJson({"outdoor": {"valid": false}, "rooms": []})!;
      expect(s.rooms, isEmpty);
      expect(s.outdoor!.valid, isFalse);
    });

    test("rooms present, outdoor absent: rooms without outdoor", () {
      final s = VentilationState.fromJson({"rooms": [fourRooms()["rooms"][0]]})!;
      expect(s.outdoor, isNull);
      expect(s.rooms, hasLength(1));
    });

    test("rooms that are not maps are skipped", () {
      final s = VentilationState.fromJson({
        "rooms": [
          "Bad",
          null,
          {"name": "Bad", "state": "missing"},
        ],
      })!;
      expect(s.rooms, hasLength(1));
      expect(s.rooms[0].name, "Bad");
    });

    test("a room without a name gets an empty name", () {
      final s = VentilationState.fromJson({
        "rooms": [
          {"state": "missing"},
        ],
      })!;
      expect(s.rooms[0].name, "");
    });

    test("outdoor without valid is not valid", () {
      final s = VentilationState.fromJson({"outdoor": {"t": 8.1, "rh": 90.0}})!;
      expect(s.outdoor!.valid, isFalse);
      expect(s.outdoor!.t, 8.1);
    });

    test("outdoor without figures keeps them null", () {
      final s = VentilationState.fromJson({"outdoor": {"valid": true}})!;
      expect(s.outdoor!.t, isNull);
      expect(s.outdoor!.rh, isNull);
    });

    test("a helps room without rh or rh_after is taken as missing", () {
      final s = VentilationState.fromJson({
        "rooms": [
          {"name": "A", "state": "helps", "rh": 70.0},
          {"name": "B", "state": "no_benefit", "rh_after": 50.0},
        ],
      })!;
      expect(s.rooms[0].state, VentilationRoomState.missing);
      expect(s.rooms[0].rh, isNull);
      expect(s.rooms[1].state, VentilationRoomState.missing);
      expect(s.rooms[1].rhAfter, isNull);
    });

    test("a non-numeric rh is taken as missing", () {
      final s = VentilationState.fromJson({
        "rooms": [
          {"name": "A", "state": "helps", "rh": "74", "rh_after": 55.0},
        ],
      })!;
      expect(s.rooms[0].state, VentilationRoomState.missing);
    });
  });

  group("states", () {
    test("an unknown state is treated as missing", () {
      final s = VentilationState.fromJson({
        "rooms": [
          {"name": "A", "state": "maybe", "rh": 70.0, "rh_after": 60.0},
          {"name": "B", "rh": 70.0, "rh_after": 60.0},
          {"name": "C", "state": 1, "rh": 70.0, "rh_after": 60.0},
        ],
      })!;
      expect(s.rooms.map((r) => r.state), everyElement(VentilationRoomState.missing));
      expect(s.rooms[0].rh, isNull);
    });
  });

  group("numbers", () {
    test("int and double are both read as numbers", () {
      final s = VentilationState.fromJson({
        "outdoor": {"t": 8, "rh": 90, "valid": true},
        "rooms": [
          {"name": "A", "state": "helps", "rh": 74, "rh_after": 55},
        ],
        "threshold": 60,
      })!;
      expect(s.outdoor!.t, 8.0);
      expect(s.outdoor!.rh, 90.0);
      expect(s.rooms[0].rh, 74.0);
      expect(s.rooms[0].rhAfter, 55.0);
      expect(s.threshold, 60.0);
    });

    test("humidity outside 0..100 is clamped", () {
      final s = VentilationState.fromJson({
        "rooms": [
          {"name": "A", "state": "helps", "rh": 120, "rh_after": -3},
        ],
      })!;
      expect(s.rooms[0].rh, 100.0);
      expect(s.rooms[0].rhAfter, 0.0);
    });

    test("threshold is optional", () {
      final s = VentilationState.fromJson({"rooms": []})!;
      expect(s.threshold, isNull);
    });
  });

  group("labels", () {
    test("absent labels give the English defaults", () {
      final l = VentilationLabels.fromJson(null);
      expect(l.title, "Ventilation");
      expect(l.helps, "Ventilating helps");
      expect(l.noBenefit, "Ventilating does not help");
      expect(l.missing, "Reading missing");
      expect(l.outside, "Outside");
      expect(l.updated, "As of");
    });

    test("given labels replace the defaults one by one", () {
      final l = VentilationLabels.fromJson({
        "title": "Lüftungsempfehlung",
        "no_benefit": "Lüften lohnt nicht",
        "updated": 3,
      });
      expect(l.title, "Lüftungsempfehlung");
      expect(l.noBenefit, "Lüften lohnt nicht");
      expect(l.helps, "Ventilating helps");
      expect(l.updated, "As of");
    });
  });
}
