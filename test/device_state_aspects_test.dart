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

import "package:flutter_dotenv/flutter_dotenv.dart";
import "package:flutter_test/flutter_test.dart";
import "package:mobile_app/app_state.dart";
import "package:mobile_app/config/functions/function_config.dart";
import "package:mobile_app/models/aspect.dart";
import "package:mobile_app/models/concept.dart";
import "package:mobile_app/models/content.dart";
import "package:mobile_app/models/content_variable.dart";
import "package:mobile_app/models/device_instance.dart";
import "package:mobile_app/models/device_state.dart";
import "package:mobile_app/models/device_type.dart";
import "package:mobile_app/models/function.dart";
import "package:mobile_app/models/sensor_pin.dart";
import "package:mobile_app/models/service.dart";
import "package:mobile_app/widgets/tabs/sensors/sensor_display.dart";

import "golden_helper.dart";

const _measure = "urn:infai:ses:measuring-function:temperature";
const _control = "urn:infai:ses:controlling-function:set-temperature";
const _otherMeasure = "urn:infai:ses:measuring-function:power";
const _otherControl = "urn:infai:ses:controlling-function:set-power";
const _brokenMeasure = "urn:infai:ses:measuring-function:broken";
const _brokenControl = "urn:infai:ses:controlling-function:set-broken";

String get onOffFunction => dotenv.env["FUNCTION_GET_ON_OFF_STATE"]!;
String get setOnFunction => dotenv.env["FUNCTION_SET_ON_STATE"]!;
String get setOffFunction => dotenv.env["FUNCTION_SET_OFF_STATE"]!;

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

DeviceState _state(String functionId, List<String> aspectIds,
        {String serviceGroupKey = "group-1", String serviceId = "service-1", bool? controlling}) =>
    DeviceState(null, serviceId, serviceGroupKey, functionId, null, controlling ?? functionId.startsWith(controllingFunctionPrefix),
        null, null, "device-1", null, null, aspectIds: aspectIds);

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
    setUp(() {
      for (final f in [
        PlatformFunction(_measure, "temperature", "concept-temperature", "Temperature"),
        PlatformFunction(_control, "set-temperature", "concept-temperature", "Set temperature"),
        PlatformFunction(_otherMeasure, "power", "concept-power", "Power"),
        PlatformFunction(_otherControl, "set-power", "concept-power", "Set power"),
      ]) {
        AppState().platformFunctions[f.id] = f;
      }
    });

    test("a reading that shares only the first aspect with the control does not pair", () {
      final net = _state(_measure, ["electricity", "generation", "net"]);
      final gross = _state(_measure, ["electricity", "generation", "gross"]);
      final control = _state(_control, ["electricity", "generation", "net"]);
      final states = [net, gross, control];

      expect(net.controlsFor(states, _control), [same(control)]);
      expect(gross.controlsFor(states, _control), isEmpty);
    });

    test("a reading on the control's aspects keeps it from a reading on more aspects", () {
      final onOff = _state(_measure, ["device"]);
      final light = _state(_measure, ["device", "lighting"]);
      final control = _state(_control, ["device"]);
      final states = [onOff, light, control];

      expect(onOff.controlsFor(states, _control), [same(control)]);
      expect(light.controlsFor(states, _control), isEmpty);
    });

    test("an exact reading wins whatever the order", () {
      final air = _state(_measure, ["air"]);
      final target = _state(_measure, ["air", "target"]);
      final control = _state(_control, ["air"]);

      for (final states in [
        [target, air, control],
        [control, air, target],
      ]) {
        expect(air.controlsFor(states, _control), [same(control)]);
        expect(target.controlsFor(states, _control), isEmpty);
      }
    });

    test("a control on fewer aspects pairs with the one reading containing them", () {
      final indoor = _state(_measure, ["air", "indoor"]);
      final control = _state(_control, ["air"]);

      expect(indoor.controlsFor([indoor, control], _control), [same(control)]);
    });

    test("a control on fewer aspects than two equally small readings pairs with neither", () {
      final indoor = _state(_measure, ["air", "indoor"]);
      final outdoor = _state(_measure, ["air", "outdoor"]);
      final control = _state(_control, ["air"]);
      final states = [indoor, outdoor, control];

      expect(indoor.controlsFor(states, _control), isEmpty);
      expect(outdoor.controlsFor(states, _control), isEmpty);
    });

    test("among readings containing the control's aspects the smallest one pairs", () {
      final indoor = _state(_measure, ["air", "indoor"]);
      final indoorTarget = _state(_measure, ["air", "indoor", "target"]);
      final control = _state(_control, ["air"]);
      final states = [indoorTarget, indoor, control];

      expect(indoor.controlsFor(states, _control), [same(control)]);
      expect(indoorTarget.controlsFor(states, _control), isEmpty);
    });

    test("all readings on the control's aspects pair, also from different services", () {
      final first = _state(_measure, ["unspecified"], serviceId: "service-1");
      final second = _state(_measure, ["unspecified"], serviceId: "service-2");
      final control = _state(_control, ["unspecified"]);
      final states = [first, second, control];

      expect(first.controlsFor(states, _control), [same(control)]);
      expect(second.controlsFor(states, _control), [same(control)]);
      expect(DeviceState.pairedReadings(control, [first, second], [control]), [same(first), same(second)]);
    });

    test("a control on fewer aspects leaves a reading that has an exact control", () {
      final reading = _state(_measure, ["device", "lighting"]);
      final exact = _state(_control, ["device", "lighting"]);
      final fewer = _state(_control, ["device"]);

      expect(reading.controlsFor([reading, exact, fewer], _control), [same(exact)]);
      expect(DeviceState.pairedReadings(fewer, [reading], [exact, fewer]), isEmpty);
      final onOff = _state(onOffFunction, ["device", "lighting"]);
      final on = _state(setOnFunction, ["device"]);
      final off = _state(setOffFunction, ["device", "lighting"]);
      expect(onOff.controlsFor([onOff, on, off], setOnFunction), [same(on)],
          reason: "only a control of the same function settles a reading");
    });

    test("a control on fewer aspects still picks a reading left without an exact control", () {
      final lighting = _state(_measure, ["device", "lighting"]);
      final power = _state(_measure, ["device", "power"]);
      final exact = _state(_control, ["device", "lighting"]);
      final fewer = _state(_control, ["device"]);
      final states = [lighting, power, exact, fewer];

      expect(lighting.controlsFor(states, _control), [same(exact)]);
      expect(power.controlsFor(states, _control), [same(fewer)]);
      final socket = _state(_measure, ["device", "power", "socket"]);
      expect(socket.controlsFor([lighting, socket, exact, fewer], _control), [same(fewer)],
          reason: "the smallest set is sought among the readings left over");
    });

    test("readings tying on one aspect set all pair, as a group's device classes do", () {
      DeviceState member(String functionId, List<String> aspectIds, String deviceClassId) => DeviceState(null, null,
          null, functionId, null, functionId.startsWith(controllingFunctionPrefix), "group-1", deviceClassId, null, null,
          null, aspectIds: aspectIds);
      final first = member(onOffFunction, ["device", "lighting"], "class-1");
      final second = member(onOffFunction, ["device", "lighting"], "class-2");
      final on = member(setOnFunction, ["device"], "class-1");
      final states = [first, second, on];

      expect(first.controlsFor(states, setOnFunction), [same(on)]);
      expect(second.controlsFor(states, setOnFunction), [same(on)]);
    });

    test("a concept without its base characteristic does not break the pairing", () {
      AppState().concepts["concept-broken"] = Concept("concept-broken", "Broken", "missing", []);
      for (final f in [
        PlatformFunction(_brokenMeasure, "broken", "concept-broken", "Broken"),
        PlatformFunction(_brokenControl, "set-broken", "concept-broken", "Set broken"),
      ]) {
        AppState().platformFunctions[f.id] = f;
      }
      final reading = _state(_measure, ["air"]);
      final broken = _state(_brokenMeasure, ["air", "indoor"]);
      final control = _state(_control, ["air"]);
      final brokenControl = _state(_brokenControl, ["air", "indoor"]);
      final states = [reading, broken, control, brokenControl];

      expect(reading.controlsFor(states, _control), [same(control)]);
      expect(broken.controlsFor(states, _brokenControl), [same(brokenControl)],
          reason: "the relation still comes from the concept");
    });

    test("a special config that relates no control keeps its readings unpaired, whatever the concept", () {
      final temperature = dotenv.env["FUNCTION_GET_TEMPERATURE"]!;
      AppState().platformFunctions[temperature] =
          PlatformFunction(temperature, "temperature", "concept-temperature", "Temperature");
      final reading = _state(temperature, ["air"]);

      expect(reading.controlsFor([reading, _state(_control, ["air"])], _control), isEmpty);
    });

    test("a control on more aspects than measured does not pair", () {
      final measurement = _state(_measure, ["a"]);

      expect(measurement.controlsFor([measurement, _state(_control, ["a", "b"])], _control), isEmpty);
      expect(measurement.controlsFor([measurement, _state(_control, ["a", "b"]), _state(_control, ["a", "c"])], _control),
          isEmpty);
      expect(_state(_measure, ["a", "b"]).controlsFor([_state(_control, ["a", "c"])], _control), isEmpty,
          reason: "overlapping sets do not pair either");
    });

    test("no aspects pair only with no aspects", () {
      final plain = _state(_measure, []);
      final measurement = _state(_measure, ["a"]);
      final control = _state(_control, []);
      final states = [plain, measurement, control];

      expect(plain.controlsFor(states, _control), [same(control)]);
      expect(measurement.controlsFor(states, _control), isEmpty);
      expect(measurement.controlsFor([measurement, control], _control), isEmpty,
          reason: "not even as the only reading");
      expect(plain.controlsFor([plain, _state(_control, ["a"])], _control), isEmpty);
    });

    test("another service group neither pairs nor competes", () {
      final indoor = _state(_measure, ["air", "indoor"]);
      final outdoor = _state(_measure, ["air", "outdoor"], serviceGroupKey: "other");
      final control = _state(_control, ["air"]);
      final states = [indoor, outdoor, control];

      expect(indoor.controlsFor(states, _control), [same(control)]);
      expect(outdoor.controlsFor(states, _control), isEmpty);
      expect(indoor.controlsFor([indoor, _state(_control, ["air"], serviceGroupKey: "other")], _control), isEmpty);
    });

    test("a control of a function unrelated to the reading neither pairs nor lets its readings compete", () {
      final indoor = _state(_measure, ["air", "indoor"]);
      final power = _state(_otherMeasure, ["air", "outdoor"]);
      final control = _state(_control, ["air"]);
      final unrelated = _state(_otherControl, ["air", "indoor"]);
      final states = [indoor, power, control, unrelated];

      expect(indoor.controlsFor(states, _otherControl), isEmpty);
      expect(indoor.controlsFor(states, _control), [same(control)]);
      expect(indoor.controlsFor([indoor, _state(_measure, ["air", "indoor"], controlling: false)], _measure), isEmpty,
          reason: "a reading is no control");
    });

    test("two equal controls are all returned, for the caller to reject", () {
      final measurement = _state(_measure, ["a", "b"]);
      final states = [measurement, _state(_control, ["a", "b"]), _state(_control, ["b", "a"])];

      expect(measurement.controlsFor(states, _control), hasLength(2));
    });
  });

  group("DeviceState.legacyMatchAspects", () {
    List<DeviceState> match(DeviceState reading, List<DeviceState> controls) =>
        DeviceState.legacyMatchAspects(controls, reading.aspectIds);

    test("an equal aspect set wins over a subset", () {
      final exact = _state(_control, ["b", "a"]);

      expect(match(_state(_measure, ["a", "b"]), [_state(_control, ["a"]), exact]), [same(exact)]);
    });

    test("a unique control on a subset of the measured aspects counts", () {
      final control = _state(_control, ["b"]);

      expect(match(_state(_measure, ["a", "b"]), [control]), [same(control)]);
    });

    test("several controls on a subset fall back to the first aspect", () {
      final first = _state(_control, ["a"]);

      expect(match(_state(_measure, ["a", "b"]), [first, _state(_control, ["b"])]), [same(first)]);
    });

    test("overlapping sets and supersets pair by the first match on the first aspect", () {
      final first = _state(_control, ["a", "b"]);

      expect(match(_state(_measure, ["a"]), [first, _state(_control, ["a", "c"])]), [same(first)]);
      final overlap = _state(_control, ["a", "c"]);
      expect(match(_state(_measure, ["a", "b"]), [overlap]), [same(overlap)]);
      expect(match(_state(_measure, ["a", "b"]), [_state(_control, ["b", "c"])]), isEmpty,
          reason: "no equal set, no subset and another first aspect");
    });

    test("without aspects only candidates without aspects match", () {
      expect(match(_state(_measure, ["a"]), [_state(_control, [])]), isEmpty);
      expect(match(_state(_measure, []), [_state(_control, ["a"])]), isEmpty);
      expect(match(_state(_measure, []), [_state(_control, [])]), hasLength(1));
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
