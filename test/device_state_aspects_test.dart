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

import "dart:convert";

import "package:flutter_test/flutter_test.dart";
import "package:mobile_app/app_state.dart";
import "package:mobile_app/models/aspect.dart";
import "package:mobile_app/models/content.dart";
import "package:mobile_app/models/content_variable.dart";
import "package:mobile_app/models/device_instance.dart";
import "package:mobile_app/models/device_state.dart";
import "package:mobile_app/models/device_type.dart";
import "package:mobile_app/models/sensor_pin.dart";
import "package:mobile_app/models/service.dart";
import "package:mobile_app/widgets/tabs/sensors/sensor_display.dart";

import "golden_helper.dart";

const _measure = "urn:infai:ses:measuring-function:temperature";
const _control = "urn:infai:ses:controlling-function:set-temperature";

DeviceInstance _device(String id) =>
    DeviceInstance(id, "local-$id", "name-$id", null, "dt", false, "owner", "display-$id", DeviceConnectionStatus.unknown);

/// A content variable as a device-repository read returns it: aspect_id is
/// the alphabetically first entry of aspect_ids.
ContentVariable _variable(String name, String functionId, List<String>? aspectIds, {String? aspectId}) => ContentVariable(
    "cv-$name", name, null, null, aspectId ?? (aspectIds == null ? null : ([...aspectIds]..sort()).first), functionId,
    "https://schema.org/Float", null, null, null, aspectIds);

DeviceType _deviceType(String id, List<ContentVariable> outputs) {
  final service = Service("service-1", "local-service-1", "Service 1", "", "protocol-1", "request", "group-1", null,
      [Content("content-1", "json", "segment-1", ContentVariable("root", "root", null, null, null, null,
          "https://schema.org/StructuredValue", outputs, null, null))]);
  return DeviceType(id, "Type", "", "class-1", [service], null);
}

DeviceState _state(String functionId, List<String> aspectIds, {String serviceGroupKey = "group-1", bool? controlling}) =>
    DeviceState(null, "service-1", serviceGroupKey, functionId, null, controlling ?? functionId == _control, null, null,
        "device-1", null, null, aspectIds: aspectIds);

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(resetAppStateForGolden);

  group("ContentVariable.effectiveAspects", () {
    test("prefers the list, sorted, over the single id", () {
      expect(_variable("v", _measure, ["b", "a"], aspectId: "a").effectiveAspects, ["a", "b"]);
    });

    test("falls back to the single id when the list is absent or empty", () {
      expect(_variable("v", _measure, null, aspectId: "a").effectiveAspects, ["a"]);
      expect(_variable("v", _measure, [], aspectId: "a").effectiveAspects, ["a"]);
      expect(_variable("v", _measure, null, aspectId: "").effectiveAspects, isEmpty);
    });

    test("keeps aspect_ids through JSON and omits it when absent", () {
      final json = _variable("v", _measure, ["b", "a"]).toJson();
      expect(json["aspect_ids"], ["b", "a"]);
      expect(ContentVariable.fromJson(jsonDecode(jsonEncode(json))).aspect_ids, ["b", "a"]);
      expect(_variable("v", _measure, null, aspectId: "a").toJson().containsKey("aspect_ids"), isFalse);
    });
  });

  group("StateHelper.getStates", () {
    test("two outputs sharing their first aspect yield two states", () {
      final type = _deviceType("dt-shared-first", [
        _variable("inside", _measure, ["air", "inside"]),
        _variable("outside", _measure, ["outside", "air"]),
      ]);
      final states = StateHelper.getStates(type, _device("device-1"));

      expect(states.map((s) => s.aspectIds), [
        ["air", "inside"],
        ["air", "outside"],
      ]);
      expect(states.map((s) => s.aspectId), ["air", "air"]);
      expect(states.map((s) => s.path), ["root.inside", "root.outside"]);
    });

    test("outputs with the same aspect set still collapse into one state", () {
      final type = _deviceType("dt-same-set", [
        _variable("first", _measure, ["b", "a"]),
        _variable("second", _measure, ["a", "b"]),
        _variable("legacy", _measure, null, aspectId: "c"),
        _variable("legacy-again", _measure, ["c"]),
      ]);
      final states = StateHelper.getStates(type, _device("device-1"));

      expect(states.map((s) => s.aspectIds), [
        ["a", "b"],
        ["c"],
      ]);
    });
  });

  group("DeviceState.controlsFor", () {
    test("an equal aspect set wins over a subset", () {
      final measurement = _state(_measure, ["a", "b"]);
      final exact = _state(_control, ["b", "a"]);
      final states = [measurement, _state(_control, ["a"]), exact];

      expect(measurement.controlsFor(states, _control), [same(exact)]);
    });

    test("a unique control on a subset of the measured aspects counts", () {
      final measurement = _state(_measure, ["a", "b"]);
      final control = _state(_control, ["a"]);

      expect(measurement.controlsFor([measurement, control], _control), [same(control)]);
    });

    test("several controls on a subset fall back to the first aspect", () {
      final measurement = _state(_measure, ["a", "b"]);
      final first = _state(_control, ["a"]);
      final states = [measurement, first, _state(_control, ["b"])];

      expect(measurement.controlsFor(states, _control), [same(first)]);
    });

    test("a control on more aspects than measured pairs by the first aspect, as before", () {
      final measurement = _state(_measure, ["a"]);
      final control = _state(_control, ["a", "b"]);

      expect(measurement.controlsFor([measurement, control], _control), [same(control)]);
    });

    test("overlapping sets pair by the first aspect, as before", () {
      final measurement = _state(_measure, ["a", "b"]);
      final control = _state(_control, ["a", "c"]);

      expect(measurement.controlsFor([measurement, control], _control), [same(control)]);
      expect(measurement.controlsFor([measurement, _state(_control, ["b", "c"])], _control), isEmpty,
          reason: "no equal set, no subset and another first aspect");
    });

    test("the first-aspect fallback picks the first match, the one control it stood for before", () {
      final measurement = _state(_measure, ["a"]);
      final first = _state(_control, ["a", "b"]);
      final states = [measurement, first, _state(_control, ["a", "c"])];

      expect(measurement.controlsFor(states, _control), [same(first)]);
    });

    test("single aspects pair as before", () {
      final measurement = _state(_measure, ["a"]);
      final control = _state(_control, ["a"]);

      expect(measurement.controlsFor([measurement, control], _control), [same(control)]);
      expect(measurement.controlsFor([measurement, _state(_control, [])], _control), isEmpty,
          reason: "a control without aspect never paired with a measurement that has one");
      final plain = _state(_measure, []);
      expect(plain.controlsFor([plain, _state(_control, ["a"])], _control), isEmpty,
          reason: "nor a measurement without aspect with a control that has one");
      expect(measurement.controlsFor([measurement, _state(_control, ["b"])], _control), isEmpty);
      expect(measurement.controlsFor([measurement, _state(_control, ["a"], serviceGroupKey: "other")], _control), isEmpty);
      expect(measurement.controlsFor([measurement, _state(_measure, ["a"], controlling: false)], _measure), isEmpty);
    });

    test("two equal controls are all returned, for the caller to reject", () {
      final measurement = _state(_measure, ["a", "b"]);
      final states = [measurement, _state(_control, ["a", "b"]), _state(_control, ["b", "a"])];

      expect(measurement.controlsFor(states, _control), hasLength(2));
    });
  });

  group("aspect labels", () {
    final aspects = [
      Aspect("air", "Air", [Aspect("inside", "Inside", null), Aspect("outside", "Outside", null)]),
      Aspect("water", "Water", null),
    ];

    test("joins the names in the list's order", () {
      expect(joinAspectNames(aspects, ["water", "inside"]), "Water, Inside");
      expect(joinAspectNames(aspects, ["air"]), "Air");
    });

    test("an unknown aspect contributes the placeholder, or nothing", () {
      expect(joinAspectNames(aspects, ["air", "gone"], missing: "MISSING"), "Air, MISSING");
      expect(joinAspectNames(aspects, ["air", "gone"]), "Air");
    });

    test("sensor subtitles tell apart states sharing their first aspect", () {
      for (final a in aspects) {
        AppState().aspects[a.id] = a;
      }
      final inside = _state(_measure, ["air", "inside"]);
      final outside = _state(_measure, ["air", "outside"]);
      final siblings = [inside, outside];

      expect(sensorSubtitle(inside, siblings, null), "Air, Inside");
      expect(sensorSubtitle(outside, siblings, null), "Air, Outside");
    });
  });

  group("SensorPin", () {
    final inside = _state(_measure, ["air", "inside"]);
    final outside = _state(_measure, ["air", "outside"]);

    test("a new pin stores the sorted list next to the first aspect", () {
      final json = SensorPin.of(outside).toJson();

      expect(json["aspectIds"], ["air", "outside"]);
      expect(json["aspectId"], "air");
    });

    test("a new pin survives a round trip and finds its own state", () {
      final pin = SensorPin.of(outside);
      final restored = SensorPin.fromJson(jsonDecode(jsonEncode(pin.toJson())));

      expect(restored, pin);
      expect(restored.hashCode, pin.hashCode);
      expect(restored.findIn([inside, outside]), same(outside));
    });

    test("pins of states sharing their first aspect differ", () {
      expect(SensorPin.of(inside), isNot(SensorPin.of(outside)));
    });

    Map<String, dynamic> legacyJson(String? aspectId) => {
          "deviceId": "device-1",
          "functionId": _measure,
          "aspectId": aspectId,
          "serviceGroupKey": "group-1",
          "isControlling": false,
        };

    test("an old pin finds the one state containing its aspect", () {
      final pin = SensorPin.fromJson(legacyJson("inside"));
      final water = _state(_measure, ["water"]);

      expect(pin.aspectIds, isNull);
      expect(pin.findIn([inside, outside, water]), same(inside));
      expect(SensorPin.fromJson(legacyJson("water")).findIn([inside, water]), same(water));
    });

    test("an old pin whose aspect several states contain is not found", () {
      expect(SensorPin.fromJson(legacyJson("air")).findIn([inside, outside]), isNull);
    });

    test("an old pin prefers the state on exactly its aspect", () {
      // A group of devices carrying [air, inside] gets the single row [air]
      // next to the combination; before aspect lists both were one state.
      final air = _state(_measure, ["air"]);

      expect(SensorPin.fromJson(legacyJson("air")).findIn([inside, air, outside]), same(air));
    });

    test("an old pin without aspect finds the state without aspect", () {
      final plain = _state(_measure, []);

      expect(SensorPin.fromJson(legacyJson(null)).findIn([inside, plain]), same(plain));
    });

    test("an old pin that resolves is upgraded to the new format", () {
      final pin = SensorPin.fromJson({...legacyJson("inside"), "alias": "Indoors"});
      final upgraded = pin.upgradedIn([inside, outside])!;

      expect(upgraded.aspectIds, ["air", "inside"]);
      expect(upgraded.aspectId, "air");
      expect(upgraded.alias, "Indoors");
      expect(upgraded, SensorPin.of(inside), reason: "so picking the state again reads as already added");
      expect(upgraded.findIn([inside, outside]), same(inside));
    });

    test("an ambiguous old pin and a new pin are not upgraded", () {
      expect(SensorPin.fromJson(legacyJson("air")).upgradedIn([inside, outside]), isNull);
      expect(SensorPin.of(inside).upgradedIn([inside, outside]), isNull);
    });

    test("an old pin keeps its shape when written back", () {
      final json = SensorPin.fromJson(legacyJson("air")).toJson();

      expect(json["aspectIds"], isNull);
      expect(json["aspectId"], "air");
    });
  });
}
