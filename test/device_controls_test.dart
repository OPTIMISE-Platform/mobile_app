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
import "package:mobile_app/models/characteristic.dart";
import "package:mobile_app/models/concept.dart";
import "package:mobile_app/models/content_variable.dart";
import "package:mobile_app/models/device_group.dart";
import "package:mobile_app/models/device_instance.dart";
import "package:mobile_app/models/device_state.dart";
import "package:mobile_app/models/function.dart";
import "package:mobile_app/shared/device_controls.dart";

import "golden_helper.dart";

const _tempGet = "urn:infai:ses:measuring-function:temperature";
const _tempSet = "urn:infai:ses:controlling-function:set-temperature";

/// The fields `DeviceState.kt` keeps in a control id, in `getId()`.
const _idFields = [
  "deviceId",
  "groupId",
  "functionId",
  "aspectId",
  "path",
  "deviceClassId",
  "serviceGroupKey",
  "serviceId",
  "name",
  "serviceGroupName",
];

Map<String, dynamic> _idOf(Map<String, dynamic> json) => {
      for (final field in _idFields)
        if (json[field] != null) field: json[field],
    };

void main() {
  late final String onOff;
  late final String setOn;
  late final String setOff;

  setUpAll(() async {
    await setUpGoldenEnvironment();
    onOff = dotenv.env["FUNCTION_GET_ON_OFF_STATE"]!;
    setOn = dotenv.env["FUNCTION_SET_ON_STATE"]!;
    setOff = dotenv.env["FUNCTION_SET_OFF_STATE"]!;
  });

  Characteristic temperature({double? min = 5, double? max = 30, String type = ContentVariable.float, String unit = "°C"}) =>
      Characteristic("char-temp", "Temperature", type, min, max, null, null, unit, null);

  void setUpMetadata(Characteristic temperatureCharacteristic) {
    final state = AppState();
    state.platformFunctions[onOff] = PlatformFunction(onOff, "get on", "concept-on-off", "Power");
    state.platformFunctions[setOn] = PlatformFunction(setOn, "on", "concept-on-off", "On");
    state.platformFunctions[setOff] = PlatformFunction(setOff, "off", "concept-on-off", "Off");
    state.platformFunctions[_tempGet] = PlatformFunction(_tempGet, "get temperature", "concept-temp", "Temperature");
    state.platformFunctions[_tempSet] = PlatformFunction(_tempSet, "set temperature", "concept-temp", "Set temperature");
    state.concepts["concept-temp"] = Concept("concept-temp", "temperature", "char-temp", [temperatureCharacteristic]);
    // A config built before the concepts were there has no characteristic.
    reinit();
  }

  setUp(() => setUpMetadata(temperature()));

  tearDown(resetAppStateForGolden);

  DeviceState deviceState(DeviceInstance d, String functionId, bool controlling,
      {dynamic value, String path = "path", List<String> aspects = const ["air"]}) {
    final s = DeviceState(value, "service-1", "group-1", functionId, null, controlling, null, null, d.id, path, "Lamp group",
        aspectIds: aspects);
    s.deviceInstance = d;
    return s;
  }

  DeviceInstance device() => DeviceInstance("device-1", "device-1-local", "Heater", null, "device-type-1", false, "owner-1", "Heater",
      DeviceConnectionStatus.online);

  group("device entries", () {
    test("an on/off reading with its controls is a toggle whose id fields are those of the unchanged payload", () {
      final d = device();
      final reading = deviceState(d, onOff, false, value: true, path: "on");
      d.states.addAll([reading, deviceState(d, setOn, true, path: "set-on"), deviceState(d, setOff, true, path: "set-off")]);

      final entries = deviceControlEntries(d.states);

      expect(entries, hasLength(1));
      expect(entries.single.kind, ControlKind.toggle);
      // What the app sent for an entry before value controls existed.
      final before = jsonDecode(jsonEncode(reading)) as Map<String, dynamic>;
      final after = jsonDecode(jsonEncode(controlEntryJson(entries.single, null))) as Map<String, dynamic>;
      expect(_idOf(after), _idOf(before), reason: "Android stores the id; a changed one orphans the added control");
      expect(after.keys.toSet().difference(before.keys.toSet()), {"kind"});
      expect(before.keys.toSet().difference(after.keys.toSet()), {"deviceInstance", "deviceGroup"},
          reason: "the platform side reads neither");
      expect(after["kind"], "toggle");
      expect(after.containsKey("min"), isFalse);
    });

    test("a toggle without a control is not offered", () {
      final d = device();
      d.states.add(deviceState(d, onOff, false, value: true));

      expect(deviceControlEntries(d.states), isEmpty);
    });

    test("a reading with one control that has a range is a range entry", () {
      final d = device();
      final reading = deviceState(d, _tempGet, false, value: 21.5, path: "t");
      d.states.addAll([reading, deviceState(d, _tempSet, true, path: "set-t")]);

      final entries = deviceControlEntries(d.states);

      expect(entries, hasLength(1));
      expect(entries.single.kind, ControlKind.range);
      expect(entries.single.state, same(reading));
      final json = jsonDecode(jsonEncode(controlEntryJson(entries.single, 21.5))) as Map<String, dynamic>;
      expect(json["kind"], "range");
      expect([json["min"], json["max"], json["step"]], [5.0, 30.0, 0.5]);
      expect(json["unit"], "°C");
      expect(json["integer"], isFalse);
      expect(json["value"], 21.5);
    });

    test("an integer characteristic steps by one", () {
      setUpMetadata(temperature(type: ContentVariable.integer, unit: ""));
      final d = device();
      d.states.addAll([deviceState(d, _tempGet, false, path: "t"), deviceState(d, _tempSet, true, path: "set-t")]);

      final range = deviceControlEntries(d.states).single.range!;

      expect([range.min, range.max, range.step, range.integer, range.unit], [5.0, 30.0, 1.0, true, null]);
    });

    test("a characteristic without a minimum and maximum, or not a number, is not offered", () {
      final d = device();
      d.states.addAll([deviceState(d, _tempGet, false, path: "t"), deviceState(d, _tempSet, true, path: "set-t")]);

      for (final c in [
        temperature(min: null),
        temperature(max: null),
        temperature(min: 30, max: 30),
        temperature(min: 31, max: 30),
        temperature(type: ContentVariable.string),
      ]) {
        setUpMetadata(c);
        expect(deviceControlEntries(d.states), isEmpty, reason: "min ${c.min_value}, max ${c.max_value}, ${c.type}");
      }
    });

    test("two controls for one reading are ambiguous and offer nothing", () {
      final d = device();
      d.states.addAll([
        deviceState(d, _tempGet, false, path: "t"),
        deviceState(d, _tempSet, true, path: "set-a"),
        // Same service group and aspects, so the reading pairs with both.
        DeviceState(null, "service-2", "group-1", _tempSet, null, true, null, null, d.id, "set-b", null, aspectIds: const ["air"])
          ..deviceInstance = d,
      ]);

      expect(deviceControlEntries(d.states), isEmpty);
    });
  });

  group("group entries", () {
    DeviceGroup group({required List<(String function, String deviceClass)> criteria}) {
      final g = DeviceGroup("group-1", "All heaters", [
        for (final (function, deviceClass) in criteria)
          DeviceGroupCriteria()
            ..function_id = function
            ..device_class_id = deviceClass
      ], "", [], null);
      g.prepareStates();
      return g;
    }

    test("an on/off reading with one control for each direction is a toggle", () {
      final g = group(criteria: [(onOff, "lamp"), (setOn, "lamp"), (setOff, "lamp")]);

      final entries = groupControlEntries(g.shownStates, g.states);

      expect(entries, hasLength(1));
      expect(entries.single.kind, ControlKind.toggle);
      expect(entries.single.state.groupId, "group-1");
      expect(entries.single.state.deviceId, isNull);
    });

    test("controls of several device classes leave a group without a toggle", () {
      final g = group(criteria: [(onOff, "lamp"), (setOn, "lamp"), (setOff, "lamp"), (setOn, "plug"), (setOff, "plug")]);

      expect(groupControlEntries(g.shownStates, g.states), isEmpty);
    });

    test("a group without the control for one direction has no toggle", () {
      final g = group(criteria: [(onOff, "lamp"), (setOn, "lamp")]);

      expect(groupControlEntries(g.shownStates, g.states), isEmpty);
    });

    test("one control for a reading makes a range entry, two do not", () {
      final one = group(criteria: [(_tempGet, "heater"), (_tempSet, "heater")]);
      final entries = groupControlEntries(one.shownStates, one.states);
      expect(entries.map((e) => e.kind), [ControlKind.range]);
      expect(entries.single.range!.max, 30.0);

      final two = group(criteria: [(_tempGet, "heater"), (_tempSet, "heater"), (_tempSet, "radiator")]);
      expect(groupControlEntries(two.shownStates, two.states), isEmpty);
    });

    test("a group of thermostats pairs its setpoint with the control of the same aspect", () {
      // As the platform keeps a thermostat group: a set-temperature control per
      // aspect and one for the device class.
      DeviceGroupCriteria criterion(String function, {String aspect = "", String deviceClass = ""}) => DeviceGroupCriteria()
        ..function_id = function
        ..aspect_id = aspect
        ..device_class_id = deviceClass;
      final g = DeviceGroup("group-1", "Thermostats", [
        criterion(_tempGet, aspect: "target"),
        criterion(_tempSet, aspect: "target"),
        criterion(_tempSet, aspect: "air"),
        criterion(_tempSet, deviceClass: thermostatDeviceClass),
      ], "", [], null);
      g.prepareStates();

      final entries = groupControlEntries(g.shownStates, g.states);

      expect(entries, hasLength(1));
      expect(entries.single.state.aspectId, "target");
      expect(controlOfReading(entries.single.state, g.states, isGroup: true)?.aspectId, "target");
      expect(groupIsThermostats(g), isTrue);
    });

    test("a group is of thermostats only when its criteria name no other device class", () {
      DeviceGroup withClasses(List<String> classes) => DeviceGroup("group-1", "Mixed", [
            for (final c in classes)
              DeviceGroupCriteria()
                ..function_id = _tempSet
                ..device_class_id = c
          ], "", [], null);

      expect(groupIsThermostats(withClasses([thermostatDeviceClass])), isTrue);
      expect(groupIsThermostats(withClasses([thermostatDeviceClass, "boiler"])), isFalse);
      expect(groupIsThermostats(withClasses([])), isFalse);
    });
  });

  group("thermostat setpoints", () {
    const celsius = "urn:infai:ses:characteristic:5ba31623-0ccb-4488-bfb7-f73b50e03b5a";

    setUp(() {
      // Degree Celsius as the platform has it: no maximum.
      final state = AppState();
      state.concepts["concept-temp"] = Concept("concept-temp", "temperature", celsius,
          [Characteristic(celsius, "Degree Celsius", ContentVariable.float, -273.15, null, null, null, "°C", null)]);
      reinit();
    });

    test("a thermostat's setpoint without a maximum gets the range a thermostat accepts", () {
      final d = device();
      final reading = deviceState(d, _tempGet, false, value: 21.5, path: "t", aspects: const [targetAspect]);
      d.states.addAll([reading, deviceState(d, _tempSet, true, path: "set-t", aspects: const [targetAspect])]);

      final entries = deviceControlEntries(d.states, thermostat: true);

      expect(entries, hasLength(1));
      final range = entries.single.range!;
      expect([range.min, range.max, range.step, range.unit], [5.0, 30.0, 0.5, "°C"]);
    });

    test("a thermostat's external temperature input gets no slider beside its setpoint", () {
      // As the Aqara SRTS-A01: the room temperature pairs with the input that
      // stands in for the thermostat's own sensor, the setpoint with its own.
      final d = device();
      final setpoint = deviceState(d, _tempGet, false, value: 21.5, path: "setpoint", aspects: const [targetAspect]);
      d.states.addAll([
        setpoint,
        deviceState(d, _tempSet, true, path: "set-setpoint", aspects: const [targetAspect]),
        deviceState(d, _tempGet, false, value: 19.0, path: "local"),
        deviceState(d, _tempSet, true, path: "external-input"),
      ]);

      final entries = deviceControlEntries(d.states, thermostat: true);

      expect(entries.map((e) => e.state), [same(setpoint)], reason: "one slider per thermostat, the setpoint");
    });

    test("any other device's setpoint without a maximum gets no slider", () {
      final d = device();
      d.states.addAll([deviceState(d, _tempGet, false, value: 55, path: "t"), deviceState(d, _tempSet, true, path: "set-t")]);

      expect(deviceControlEntries(d.states), isEmpty, reason: "a boiler sets its water far above 30 °C");
    });
  });

  group("values", () {
    test("a toggle value is a boolean, mixed counts as off and unknown as nothing", () {
      expect(controlValue(ControlKind.toggle, true, isGroup: false), true);
      expect(controlValue(ControlKind.toggle, [true], isGroup: false), true);
      expect(controlValue(ControlKind.toggle, [true, null], isGroup: true), true);
      expect(controlValue(ControlKind.toggle, [true, false], isGroup: true), false);
      expect(controlValue(ControlKind.toggle, null, isGroup: true), isNull);
    });

    test("a range value is a number, a group's only when its members agree", () {
      expect(controlValue(ControlKind.range, [21], isGroup: false), 21.0);
      expect(controlValue(ControlKind.range, 21.5, isGroup: false), 21.5);
      expect(controlValue(ControlKind.range, [20, 20], isGroup: true), 20.0);
      expect(controlValue(ControlKind.range, [20, 22], isGroup: true), isNull);
      expect(controlValue(ControlKind.range, "warm", isGroup: false), isNull);
    });
  });

  group("lookup from the platform side", () {
    /// What the platform side sends back: the id fields, without the aspect list.
    DeviceState platformEntry(DeviceState reading) {
      final json = jsonDecode(jsonEncode(controlEntryJson(ControlEntry(reading, ControlKind.range), null))) as Map<String, dynamic>;
      json.remove("aspectIds");
      return DeviceState.fromJson(json);
    }

    test("a device's entry finds its reading, whose control carries the device for gateway routing", () {
      final d = device();
      final reading = deviceState(d, _tempGet, false, path: "t");
      final control = deviceState(d, _tempSet, true, path: "set-t");
      d.states.addAll([reading, control, deviceState(d, _tempGet, false, path: "other")..deviceInstance = d]);
      // Two readings at different places: the entry's path settles which.
      final found = readingForEntry(platformEntry(reading), null, d.states, isGroup: false);

      expect(found, same(reading));
      final command = controlOfReading(found!, d.states, isGroup: false)!.toCommand(22.0);
      expect(command.deviceInstance, same(d));
      expect(command.device_id, "device-1");
      expect(command.input, 22.0);
    });

    test("a group's entry finds its reading, whose control carries the group", () {
      final g = DeviceGroup("group-1", "All heaters", [
        DeviceGroupCriteria()
          ..function_id = _tempGet
          ..device_class_id = "heater",
        DeviceGroupCriteria()
          ..function_id = _tempSet
          ..device_class_id = "heater",
      ], "", [], null)
        ..prepareStates();
      final reading = g.states.firstWhere((s) => !s.isControlling);

      final found = readingForEntry(platformEntry(reading), null, g.states, isGroup: true);

      expect(found, same(reading));
      final command = controlOfReading(found!, g.states, isGroup: true)!.toCommand(22.0);
      expect(command.deviceGroup, same(g));
      expect(command.group_id, "group-1");
      expect(command.device_id, isNull);
    });

    test("an entry whose reading is gone finds none", () {
      final d = device();
      d.states.add(deviceState(d, _tempGet, false, path: "t"));
      final gone = DeviceState(null, "service-9", "group-1", _tempGet, "air", false, null, null, d.id, "gone", null);

      expect(readingForEntry(gone, null, d.states, isGroup: false), isNull);
    });
  });
}
