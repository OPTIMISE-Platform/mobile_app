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
import 'package:mobile_app/models/content.dart';
import 'package:mobile_app/models/content_variable.dart';
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/models/function.dart';
import 'package:mobile_app/models/service.dart';
import 'package:mobile_app/services/automation_engine.dart';
import 'package:mobile_app/services/process_io.dart';
import 'package:mobile_app/widgets/tabs/smart-services/automation_suggestions_load.dart';
import 'package:mobile_app/widgets/tabs/smart-services/automation_suggestions_model.dart';

const _getLevel = "urn:infai:ses:measuring-function:get-level";
const _setLevel = "urn:infai:ses:controlling-function:set-level";
const _getState = getBinaryStateFunctionId;
const _conceptLevel = "concept-level";
const _conceptBinary = "concept-binary";

final _functions = <String, PlatformFunction>{
  _getLevel: PlatformFunction(_getLevel, "Get Level", _conceptLevel, "Get Level"),
  _setLevel: PlatformFunction(_setLevel, "Set Level", _conceptLevel, "Set Level"),
  _getState: PlatformFunction(_getState, "Get Binary State", binaryStateConceptId, "Get Binary State"),
  setDeviceOnFunctionId: PlatformFunction(setDeviceOnFunctionId, "Set Device On", _conceptBinary, "Set Device On"),
  setDeviceOffFunctionId: PlatformFunction(setDeviceOffFunctionId, "Set Device Off", _conceptBinary, "Set Device Off"),
};

ContentVariable _cv(String name, {String? fn, String? ch, List<ContentVariable>? subs, List<String>? aspects}) =>
    ContentVariable(null, name, ch, null, null, fn, ContentVariable.none, subs, null, null, aspects);

Content _content(ContentVariable cv) => Content("c-${cv.name}", "json", "seg", cv);

Service _service(String id, String group, {List<ContentVariable> inputs = const [], List<ContentVariable> outputs = const []}) =>
    Service(id, "local-$id", id, "", "proto", "event", group, [for (final i in inputs) _content(i)], [for (final o in outputs) _content(o)]);

/// A lamp with a binary control service (on and off on one service) and a
/// level service whose measured level has a concept-matching set function.
DeviceType _lampType() => DeviceType("dt-lamp", "Lamp", "", "dc", [
      _service("svc-switch", "lamp",
          outputs: [_cv("state", fn: _getState, ch: "ch-bool")],
          inputs: [
            _cv("power_on", fn: setDeviceOnFunctionId, ch: "ch-bool"),
            _cv("power_off", fn: setDeviceOffFunctionId, ch: "ch-bool"),
          ]),
      _service("svc-level", "lamp",
          outputs: [_cv("value", subs: [_cv("level", fn: _getLevel, ch: "ch-int")])],
          inputs: [_cv("value", subs: [_cv("level", fn: _setLevel, ch: "ch-int")])]),
    ], null);

SuggestionTarget _binaryTarget(String device, bool value) => SuggestionTarget(device, "svc-switch", "value.state", null, value);

/// A device type with four switch channels, each with its own on and off, in one service group.
DeviceType _fourChannelType() => DeviceType("dt-four", "Four", "", "dc", [
      for (var i = 1; i <= 4; i++)
        _service("svc-ch$i", "switch",
            outputs: [_cv("state", fn: _getState, ch: "ch-bool")],
            inputs: [
              _cv("power_on", fn: setDeviceOnFunctionId, ch: "ch-bool"),
              _cv("power_off", fn: setDeviceOffFunctionId, ch: "ch-bool"),
            ]),
    ], null);

Suggestion _suggestion(List<SuggestionTarget> targets, {int? autoOffS}) => Suggestion(
      "s-1",
      SuggestionTrigger("plug", "svc-plug", "value.state", "binary", "on", "off"),
      SuggestionWindow("19:00", "02:00", const [0, 1, 2, 3, 4, 5, 6], "Europe/Berlin"),
      targets,
      autoOffS,
      SuggestionStats(291, 90, 0.31),
    );

const _names = {"plug": "Stehlampe", "lamp": "Licht EG"};

void main() {
  group("export row", () {
    final body = {
      "version": "v-1",
      "trained_at": "2026-10-28T03:12:00Z",
      "history": {"from": "2025-10-28", "to": "2026-10-28"},
      "suggestions": [
        {
          "id": "s-1",
          "trigger": {"device_id": "plug", "service_id": "svc-plug", "path": "value.state", "kind": "binary", "from": "on", "to": "off"},
          "window": {"from": "19:00", "to": "02:00", "weekdays": [0, 1, 2, 3, 4, 5, 6], "tz": "Europe/Berlin"},
          "targets": [
            {"device_id": "lamp", "service_id": "svc-switch", "path": "value.state", "function_id": null, "value": true}
          ],
          "auto_off_s": 120,
          "stats": {"occurrences": 291, "hits": 90, "confidence": 0.31, "baseline": 0.05, "lift": 6.2, "median_delay_s": 25},
        }
      ],
    };

    test("the newest list parses into the snapshot", () {
      final snapshot = parseExportSuggestions(json.encode(body));
      expect(snapshot.version, "v-1");
      expect(snapshot.trainedAt, "2026-10-28T03:12:00Z");
      expect(snapshot.suggestions, hasLength(1));
      final s = snapshot.suggestions.single;
      expect(s.id, "s-1");
      expect(s.trigger.kind, "binary");
      expect(s.trigger.from, "on");
      expect(s.trigger.to, "off");
      expect(s.window.from, "19:00");
      expect(s.window.to, "02:00");
      expect(s.window.weekdays, [0, 1, 2, 3, 4, 5, 6]);
      expect(s.targets.single.functionId, isNull);
      expect(s.targets.single.value, true);
      expect(s.autoOffS, 120);
      expect(s.stats.occurrences, 291);
      expect(s.stats.hits, 90);
      expect(s.stats.confidence, closeTo(0.31, 1e-9));
    });

    test("a suggestion without auto-off and a null from parse", () {
      final b = json.decode(json.encode(body)) as Map<String, dynamic>;
      final s0 = (b["suggestions"] as List).single as Map<String, dynamic>;
      s0["auto_off_s"] = null;
      (s0["trigger"] as Map<String, dynamic>)["from"] = null;
      (s0["trigger"] as Map<String, dynamic>)["kind"] = "button";
      final snapshot = parseExportSuggestions(json.encode(b));
      expect(snapshot.suggestions.single.autoOffS, isNull);
      expect(snapshot.suggestions.single.trigger.from, isNull);
    });

    test("an empty list of suggestions is a valid snapshot", () {
      final snapshot = parseExportSuggestions(json.encode({"suggestions": []}));
      expect(snapshot.suggestions, isEmpty);
    });

    test("a value that is no JSON object is rejected", () {
      expect(() => parseExportSuggestions("[]"), throwsFormatException);
    });

    test("suggestions that are not a list are rejected", () {
      expect(() => parseExportSuggestions(json.encode({"suggestions": "x"})), throwsFormatException);
    });
  });

  group("power triggers", () {
    Map<String, dynamic> powerEntry() => {
          "id": "s-power",
          "trigger": {
            "device_id": "plug",
            "service_id": "svc-plug",
            "path": "value.sensor.ENERGY.Power",
            "kind": "power",
            "from": "off",
            "to": "on",
            "on_above_w": 20,
            "off_below_w": 10,
            "hold_s": 60,
          },
          "window": {"from": "19:00", "to": "02:00", "weekdays": [0, 1, 2, 3, 4, 5, 6], "tz": "Europe/Berlin"},
          "targets": [
            {"device_id": "lamp", "service_id": "svc-switch", "path": "value.state", "function_id": null, "value": true}
          ],
          "auto_off_s": null,
          "stats": {"occurrences": 12, "hits": 4, "confidence": 0.33},
        };

    SuggestionTrigger powerTrigger({String to = "on"}) =>
        SuggestionTrigger("plug", "svc-plug", "value.sensor.ENERGY.Power", "power", to == "on" ? "off" : "on", to,
            onAboveW: 20, offBelowW: 10, holdS: 60);

    test("a power trigger parses its thresholds and hold time", () {
      final snapshot = parseExportSuggestions(json.encode({"suggestions": [powerEntry()]}));
      expect(snapshot.skipped, 0);
      final t = snapshot.suggestions.single.trigger;
      expect(t.kind, "power");
      expect(t.from, "off");
      expect(t.to, "on");
      expect(t.onAboveW, 20);
      expect(t.offBelowW, 10);
      expect(t.holdS, 60);
    });

    test("a binary trigger carries no thresholds", () {
      final snapshot = parseExportSuggestions(json.encode({
        "suggestions": [
          {
            "id": "s-1",
            "trigger": {"device_id": "plug", "service_id": "svc-plug", "path": "value.state", "kind": "binary", "from": "on", "to": "off"},
            "window": {"from": "19:00", "to": "02:00", "weekdays": [0], "tz": "Europe/Berlin"},
            "targets": [],
            "auto_off_s": null,
            "stats": {"occurrences": 1, "hits": 1, "confidence": 1.0},
          }
        ],
      }));
      final t = snapshot.suggestions.single.trigger;
      expect(t.onAboveW, isNull);
      expect(t.offBelowW, isNull);
      expect(t.holdS, isNull);
    });

    test("a power trigger missing a threshold or with a text value is skipped", () {
      final noThreshold = powerEntry();
      (noThreshold["trigger"] as Map<String, dynamic>).remove("on_above_w");
      final textHold = powerEntry();
      (textHold["trigger"] as Map<String, dynamic>)["hold_s"] = "60";
      final snapshot = parseExportSuggestions(json.encode({"suggestions": [noThreshold, textHold]}));
      expect(snapshot.suggestions, isEmpty);
      expect(snapshot.skipped, 2);
    });

    test("the label names the thresholds in place of the word on or off", () {
      expect(suggestionLabel(powerTrigger(), const [], _names), "Stehlampe an (> 20 W)");
      expect(suggestionLabel(powerTrigger(to: "off"), const [], _names), "Stehlampe aus (< 10 W)");
      expect(
        suggestionLabel(powerTrigger(), [(deviceId: "lamp", value: true)], _names),
        "Stehlampe an (> 20 W) → Licht EG an",
      );
    });

    test("the accept payload carries the thresholds and the hold time in the trigger", () {
      final resolved = resolveSuggestion(
        Suggestion("s-power", powerTrigger(), SuggestionWindow("19:00", "02:00", const [0, 1, 2, 3, 4, 5, 6], "Europe/Berlin"),
            [_binaryTarget("lamp", true)], null, SuggestionStats(12, 4, 0.33)),
        typesByDevice: {"lamp": _lampType()},
        functions: _functions,
        names: _names,
      );
      expect(resolved.label, "Stehlampe an (> 20 W) → Licht EG an");
      final trigger = json.decode(acceptVariables(resolved)["trigger"]!) as Map<String, dynamic>;
      expect(trigger, {
        "device_id": "plug",
        "service_id": "svc-plug",
        "path": "value.sensor.ENERGY.Power",
        "kind": "power",
        "from": "off",
        "to": "on",
        "on_above_w": 20,
        "off_below_w": 10,
        "hold_s": 60,
      });
    });
  });

  group("target resolution", () {
    test("a binary true target resolves to Set Device On and an auto-off to Set Device Off on the same service", () {
      final r = resolveSuggestion(
        _suggestion([_binaryTarget("lamp", true)], autoOffS: 120),
        typesByDevice: {"lamp": _lampType()},
        functions: _functions,
        names: _names,
      );
      expect(r.targets, hasLength(1));
      final t = r.targets.single;
      expect(t.deviceId, "lamp");
      expect(t.serviceId, "svc-switch");
      expect(t.functionId, setDeviceOnFunctionId);
      expect(t.characteristicId, "ch-bool");
      expect(t.value, true);
      expect(t.offServiceId, "svc-switch");
      expect(t.offFunctionId, setDeviceOffFunctionId);
      expect(t.offCharacteristicId, "ch-bool");
      expect(t.offValue, false);
    });

    test("a binary true target without auto-off has no off part", () {
      final r = resolveSuggestion(_suggestion([_binaryTarget("lamp", true)]),
          typesByDevice: {"lamp": _lampType()}, functions: _functions, names: _names);
      expect(r.targets.single.functionId, setDeviceOnFunctionId);
      expect(r.targets.single.offFunctionId, isNull);
      expect(r.targets.single.offValue, isNull);
    });

    test("a binary false target resolves to Set Device Off", () {
      final r = resolveSuggestion(_suggestion([_binaryTarget("lamp", false)], autoOffS: 120),
          typesByDevice: {"lamp": _lampType()}, functions: _functions, names: _names);
      final t = r.targets.single;
      expect(t.functionId, setDeviceOffFunctionId);
      expect(t.characteristicId, "ch-bool");
      expect(t.offFunctionId, isNull);
    });

    test("an auto-off resolves Set Device Off on a separate service of the device type", () {
      final type = DeviceType("dt-split", "Split", "", "dc", [
        _service("svc-on", "lamp", inputs: [_cv("power_on", fn: setDeviceOnFunctionId, ch: "ch-on")]),
        _service("svc-off", "lamp", inputs: [_cv("power_off", fn: setDeviceOffFunctionId, ch: "ch-off")]),
      ], null);
      final target = SuggestionTarget("lamp", "svc-on", "value.state", null, true);
      final r = resolveSuggestion(_suggestion([target], autoOffS: 120),
          typesByDevice: {"lamp": type}, functions: _functions, names: _names);
      final t = r.targets.single;
      expect(t.serviceId, "svc-on");
      expect(t.functionId, setDeviceOnFunctionId);
      expect(t.characteristicId, "ch-on");
      expect(t.offServiceId, "svc-off");
      expect(t.offFunctionId, setDeviceOffFunctionId);
      expect(t.offCharacteristicId, "ch-off");
      expect(t.offValue, false);
    });

    test("a binary true target without a resolvable Set Device Off stays visible with no off part", () {
      final type = DeviceType("dt-on-only", "On only", "", "dc", [
        _service("svc-on", "lamp", inputs: [_cv("power_on", fn: setDeviceOnFunctionId, ch: "ch-bool")]),
      ], null);
      final r = resolveSuggestion(_suggestion([_binaryTarget("lamp", true)], autoOffS: 120),
          typesByDevice: {"lamp": type}, functions: _functions, names: _names);
      expect(r.targets.single.functionId, setDeviceOnFunctionId);
      expect(r.targets.single.offFunctionId, isNull);
      expect(r.targets.single.offValue, isNull);
      expect(r.canAutoOff, isFalse);
      expect(r.offersAutoOff, isFalse);
    });

    test("without auto-off a device type with only Set Device On still resolves the on target", () {
      final type = DeviceType("dt-on-only", "On only", "", "dc", [
        _service("svc-on", "lamp", inputs: [_cv("power_on", fn: setDeviceOnFunctionId, ch: "ch-bool")]),
      ], null);
      final r = resolveSuggestion(_suggestion([_binaryTarget("lamp", true)]),
          typesByDevice: {"lamp": type}, functions: _functions, names: _names);
      expect(r.targets.single.functionId, setDeviceOnFunctionId);
    });

    test("a concept target resolves to the controlling function of the measured concept", () {
      final target = SuggestionTarget("lamp", "svc-level", "value.value.level", _getLevel, 50);
      final r = resolveSuggestion(_suggestion([target]),
          typesByDevice: {"lamp": _lampType()}, functions: _functions, names: _names);
      final t = r.targets.single;
      expect(t.serviceId, "svc-level");
      expect(t.functionId, _setLevel);
      expect(t.characteristicId, "ch-int");
      expect(t.value, 50);
      expect(t.offFunctionId, isNull);
    });

    test("a concept target without a controlling function of its concept is hidden", () {
      final type = DeviceType("dt-sensor", "Sensor", "", "dc", [
        _service("svc-level", "lamp", outputs: [_cv("value", subs: [_cv("level", fn: _getLevel, ch: "ch-int")])]),
      ], null);
      final target = SuggestionTarget("lamp", "svc-level", "value.value.level", _getLevel, 50);
      final r = resolveSuggestion(_suggestion([target]), typesByDevice: {"lamp": type}, functions: _functions, names: _names);
      expect(r.targets, isEmpty);
    });

    test("a target whose path is not an output of the service is hidden", () {
      final target = SuggestionTarget("lamp", "svc-level", "value.value.unknown", _getLevel, 50);
      final r = resolveSuggestion(_suggestion([target]),
          typesByDevice: {"lamp": _lampType()}, functions: _functions, names: _names);
      expect(r.targets, isEmpty);
    });

    test("a target whose device type is unknown is hidden and the label names the device", () {
      final r = resolveSuggestion(_suggestion([_binaryTarget("lamp", true)], autoOffS: 120),
          typesByDevice: {}, functions: _functions, names: _names);
      expect(r.targets, isEmpty);
      expect(r.label, "Stehlampe aus → Licht EG an");
    });

    test("one unresolvable target leaves the others", () {
      final unknown = SuggestionTarget("other", "svc-level", "value.value.level", _getLevel, 50);
      final r = resolveSuggestion(_suggestion([_binaryTarget("lamp", true), unknown]),
          typesByDevice: {"lamp": _lampType()}, functions: _functions, names: _names);
      expect(r.targets.map((t) => t.deviceId), ["lamp"]);
    });

    test("the label follows the example and names only resolved targets", () {
      final r = resolveSuggestion(_suggestion([_binaryTarget("lamp", true)], autoOffS: 120),
          typesByDevice: {"lamp": _lampType()}, functions: _functions, names: _names);
      expect(r.label, "Stehlampe aus → Licht EG an");
      expect(r.id, "s-1");
    });
  });

  group("binary detection in production shape", () {
    // In production Set Device On and Off have an empty concept_id.
    final productionFunctions = <String, PlatformFunction>{
      ..._functions,
      setDeviceOnFunctionId: PlatformFunction(setDeviceOnFunctionId, "Set Device On", "", "Set Device On"),
      setDeviceOffFunctionId: PlatformFunction(setDeviceOffFunctionId, "Set Device Off", "", "Set Device Off"),
    };
    final stairs = DeviceType("dt-stairs", "Stairs", "", "dc", [
      _service("svc-switch", "light",
          outputs: [_cv("state", fn: getBinaryStateFunctionId, ch: "ch-bool")],
          inputs: [
            _cv("power_on", fn: setDeviceOnFunctionId, ch: "ch-bool"),
            _cv("power_off", fn: setDeviceOffFunctionId, ch: "ch-bool"),
          ]),
    ], null);

    test("a binary true target with auto-off resolves although Set Device On has an empty concept", () {
      final r = resolveSuggestion(_suggestion([_binaryTarget("lamp", true)], autoOffS: 120),
          typesByDevice: {"lamp": stairs}, functions: productionFunctions, names: _names);
      final t = r.targets.single;
      expect(t.functionId, setDeviceOnFunctionId);
      expect(t.offFunctionId, setDeviceOffFunctionId);
    });

    test("a binary false target resolves to Set Device Off with an empty concept", () {
      final r = resolveSuggestion(_suggestion([_binaryTarget("lamp", false)]),
          typesByDevice: {"lamp": stairs}, functions: productionFunctions, names: _names);
      expect(r.targets.single.functionId, setDeviceOffFunctionId);
    });

    test("a measured function with the binary-state concept is binary even if its id is unknown", () {
      final type = DeviceType("dt-concept", "Concept", "", "dc", [
        _service("svc-switch", "light",
            outputs: [_cv("state", fn: "urn:infai:ses:measuring-function:other", ch: "ch-bool")],
            inputs: [_cv("power_on", fn: setDeviceOnFunctionId, ch: "ch-bool")]),
      ], null);
      final fns = {
        ...productionFunctions,
        "urn:infai:ses:measuring-function:other": PlatformFunction("urn:infai:ses:measuring-function:other", "Other", binaryStateConceptId, "Other"),
      };
      final r = resolveSuggestion(_suggestion([_binaryTarget("lamp", true)]),
          typesByDevice: {"lamp": type}, functions: fns, names: _names);
      expect(r.targets.single.functionId, setDeviceOnFunctionId);
    });

    test("a text value on the production binary state is still hidden", () {
      final r = resolveSuggestion(
          _suggestion([SuggestionTarget("light", "svc-switch", "value.state", null, "unavailable")]),
          typesByDevice: {"light": stairs}, functions: productionFunctions, names: _names);
      expect(r.targets, isEmpty);
    });
  });

  group("paths and value types", () {
    test("a device type with a root other than value resolves after the analytics prefix is stripped", () {
      final type = DeviceType("dt-sensor-root", "Sensor", "", "dc", [
        _service("svc-level", "lamp",
            outputs: [_cv("sensor", subs: [_cv("level", fn: _getLevel, ch: "ch-int")])],
            inputs: [_cv("sensor", subs: [_cv("level", fn: _setLevel, ch: "ch-int")])]),
      ], null);
      final target = SuggestionTarget("lamp", "svc-level", "value.sensor.level", _getLevel, 50);
      final r = resolveSuggestion(_suggestion([target]), typesByDevice: {"lamp": type}, functions: _functions, names: _names);
      expect(r.targets.single.functionId, _setLevel);
      expect(r.targets.single.characteristicId, "ch-int");
    });

    test("exactly one leading value. is stripped, a second one is not", () {
      final target = SuggestionTarget("lamp", "svc-level", "value.value.value.level", _getLevel, 50);
      final r = resolveSuggestion(_suggestion([target]), typesByDevice: {"lamp": _lampType()}, functions: _functions, names: _names);
      expect(r.targets, isEmpty);
    });

    test("a path without the analytics prefix is matched as it is", () {
      final type = DeviceType("dt-plain", "Plain", "", "dc", [
        _service("svc-level", "lamp",
            outputs: [_cv("POWER", fn: _getLevel, ch: "ch-int")],
            inputs: [_cv("POWER", fn: _setLevel, ch: "ch-int")]),
      ], null);
      final target = SuggestionTarget("lamp", "svc-level", "POWER", _getLevel, 50);
      final r = resolveSuggestion(_suggestion([target]), typesByDevice: {"lamp": type}, functions: _functions, names: _names);
      expect(r.targets.single.functionId, _setLevel);
    });

    test("with four switch channels the binary command goes to the measured channel 3", () {
      final target = SuggestionTarget("four", "svc-ch3", "value.state", null, true);
      final r = resolveSuggestion(_suggestion([target], autoOffS: 120),
          typesByDevice: {"four": _fourChannelType()}, functions: _functions, names: _names);
      final t = r.targets.single;
      expect(t.serviceId, "svc-ch3");
      expect(t.offServiceId, "svc-ch3");
      expect(t.functionId, setDeviceOnFunctionId);
      expect(t.offFunctionId, setDeviceOffFunctionId);
    });

    test("with four switch channels a false target goes to channel 3 as well", () {
      final target = SuggestionTarget("four", "svc-ch3", "value.state", null, false);
      final r = resolveSuggestion(_suggestion([target]),
          typesByDevice: {"four": _fourChannelType()}, functions: _functions, names: _names);
      expect(r.targets.single.serviceId, "svc-ch3");
      expect(r.targets.single.functionId, setDeviceOffFunctionId);
    });

    test("a binary target with a text value is hidden and no Set Device command is built from it", () {
      final target = SuggestionTarget("lamp", "svc-switch", "value.state", null, "unavailable");
      final r = resolveSuggestion(_suggestion([target]),
          typesByDevice: {"lamp": _lampType()}, functions: _functions, names: _names);
      expect(r.targets, isEmpty);
    });

    test("a text value without a known measured function is hidden", () {
      final type = DeviceType("dt-unknown", "Unknown", "", "dc", [
        _service("svc-on", "lamp", inputs: [_cv("power_on", fn: setDeviceOnFunctionId, ch: "ch-bool")]),
      ], null);
      final target = SuggestionTarget("lamp", "svc-on", "value.state", null, "ON");
      final r = resolveSuggestion(_suggestion([target]), typesByDevice: {"lamp": type}, functions: _functions, names: _names);
      expect(r.targets, isEmpty);
    });

    test("a bool value on a level target is hidden", () {
      final target = SuggestionTarget("lamp", "svc-level", "value.value.level", _getLevel, true);
      final r = resolveSuggestion(_suggestion([target]),
          typesByDevice: {"lamp": _lampType()}, functions: _functions, names: _names);
      expect(r.targets, isEmpty);
    });
  });

  group("broken entries and process-io failures", () {
    final body = {
      "suggestions": [
        {
          "id": "s-ok",
          "trigger": {"device_id": "plug", "service_id": "svc-plug", "path": "value.state", "kind": "binary", "from": "on", "to": "off"},
          "window": {"from": "19:00", "to": "02:00", "weekdays": [0], "tz": "Europe/Berlin"},
          "targets": [],
          "auto_off_s": null,
          "stats": {"occurrences": 1, "hits": 1, "confidence": 1.0},
        },
        {"id": "s-broken"},
      ],
    };

    test("a broken entry is left out and the rest of the list is kept", () {
      final snapshot = parseExportSuggestions(json.encode(body));
      expect(snapshot.suggestions.map((s) => s.id), ["s-ok"]);
      expect(snapshot.skipped, 1);
    });

    test("a failed process-io lookup means nothing is dismissed", () async {
      var reported = false;
      final dismissed = await isDismissed(
        () async => throw StateError("process-io down"),
        onError: (_, __) => reported = true,
      );
      expect(dismissed, isFalse);
      expect(reported, isTrue);
    });

    test("an existing dismissed variable hides the suggestion, a missing one does not", () async {
      expect(await isDismissed(() async => {"key": "x"}), isTrue);
      expect(await isDismissed(() async => null), isFalse);
    });

    test("process-io's answer for an unknown key, 200 with a null value, counts as missing", () async {
      final unknown = {"key": "automation-suggester.dismissed.x", "value": null, "unix_timestamp_in_s": 0};
      expect(ProcessIoService.storedVariable(unknown), isNull);
      expect(ProcessIoService.storedVariable(null), isNull);
      expect(await isDismissed(() async => ProcessIoService.storedVariable(unknown)), isFalse);
      final stored = {"key": "automation-suggester.dismissed.x", "value": true, "unix_timestamp_in_s": 1761570000};
      expect(await isDismissed(() async => ProcessIoService.storedVariable(stored)), isTrue);
    });

    test("a dismiss variable is bound to the instance, so it is deleted together with it", () {
      final body = ProcessIoService.variableBody("automation-suggester.dismissed.x", true, instanceId: "inst-1");
      expect(body["process_instance_id"], "inst-1");
      expect(body["value"], isTrue);
      expect(ProcessIoService.variableBody("k", 1)["process_instance_id"], "");
    });
  });

  group("accept variables", () {
    test("every variable is a string and the JSON values decode to the export shape", () {
      final resolved = resolveSuggestion(_suggestion([_binaryTarget("lamp", true)], autoOffS: 120),
          typesByDevice: {"lamp": _lampType()}, functions: _functions, names: _names);
      final vars = acceptVariables(resolved);

      expect(vars.keys, unorderedEquals(["suggestion_id", "label", "trigger", "window", "targets", "auto_off_s"]));
      expect(vars.values, everyElement(isA<String>()));
      expect(vars["suggestion_id"], "s-1");
      expect(vars["label"], "Stehlampe aus → Licht EG an");
      expect(vars["auto_off_s"], "120");

      expect(json.decode(vars["trigger"]!), {
        "device_id": "plug",
        "service_id": "svc-plug",
        "path": "value.state",
        "kind": "binary",
        "from": "on",
        "to": "off",
      });
      expect(json.decode(vars["window"]!), {"from": "19:00", "to": "02:00", "weekdays": [0, 1, 2, 3, 4, 5, 6], "tz": "Europe/Berlin"});
      expect(json.decode(vars["targets"]!), [
        {
          "device_id": "lamp",
          "service_id": "svc-switch",
          "function_id": setDeviceOnFunctionId,
          "characteristic_id": "ch-bool",
          "value": true,
          "off_service_id": "svc-switch",
          "off_function_id": setDeviceOffFunctionId,
          "off_characteristic_id": "ch-bool",
          "off_value": false,
        }
      ]);
    });

    test("without auto-off the auto_off_s is empty and the off part is null", () {
      final resolved = resolveSuggestion(_suggestion([_binaryTarget("lamp", true)]),
          typesByDevice: {"lamp": _lampType()}, functions: _functions, names: _names);
      final vars = acceptVariables(resolved);
      expect(vars["auto_off_s"], "");
      final targets = json.decode(vars["targets"]!) as List<dynamic>;
      expect((targets.single as Map)["off_function_id"], isNull);
      expect((targets.single as Map)["off_value"], isNull);
    });

    test("a concept target carries its value as JSON, not as text", () {
      final target = SuggestionTarget("lamp", "svc-level", "value.value.level", _getLevel, 50);
      final resolved = resolveSuggestion(_suggestion([target]),
          typesByDevice: {"lamp": _lampType()}, functions: _functions, names: _names);
      final targets = json.decode(acceptVariables(resolved)["targets"]!) as List<dynamic>;
      expect((targets.single as Map)["value"], 50);
      expect((targets.single as Map)["function_id"], _setLevel);
    });
  });

  group("optional auto-off", () {
    DeviceType onOnlyType() => DeviceType("dt-on-only", "On only", "", "dc", [
          _service("svc-on", "lamp", inputs: [_cv("power_on", fn: setDeviceOnFunctionId, ch: "ch-bool")]),
        ], null);

    test("a chosen duration replaces the suggested one and carries the off part", () {
      final resolved = resolveSuggestion(_suggestion([_binaryTarget("lamp", true)], autoOffS: 120),
          typesByDevice: {"lamp": _lampType()}, functions: _functions, names: _names);
      final vars = acceptVariablesFor(resolved, 180);
      expect(vars["auto_off_s"], "180");
      final target = (json.decode(vars["targets"]!) as List<dynamic>).single as Map<String, dynamic>;
      expect(target["off_function_id"], setDeviceOffFunctionId);
      expect(target["off_value"], false);
    });

    test("without the switch-off no off field is set and auto_off_s is empty", () {
      final resolved = resolveSuggestion(_suggestion([_binaryTarget("lamp", true)], autoOffS: 120),
          typesByDevice: {"lamp": _lampType()}, functions: _functions, names: _names);
      final vars = acceptVariablesFor(resolved, null);
      expect(vars["auto_off_s"], "");
      final target = (json.decode(vars["targets"]!) as List<dynamic>).single as Map<String, dynamic>;
      expect(target["off_service_id"], isNull);
      expect(target["off_function_id"], isNull);
      expect(target["off_characteristic_id"], isNull);
      expect(target["off_value"], isNull);
      expect(target["function_id"], setDeviceOnFunctionId);
    });

    test("a binary target without Set Device Off is not switchable off, neither by default nor with a duration", () {
      final resolved = resolveSuggestion(_suggestion([_binaryTarget("lamp", true)], autoOffS: 120),
          typesByDevice: {"lamp": onOnlyType()}, functions: _functions, names: _names);
      expect(resolved.canAutoOff, isFalse);
      expect(() => acceptVariablesFor(resolved, 120), throwsArgumentError);
      expect(acceptVariables(resolved)["auto_off_s"], "");
      expect(acceptVariablesFor(resolved, null)["auto_off_s"], "");
    });

    test("a suggestion without auto_off_s is not offered the switch-off even when Set Device Off resolves", () {
      final resolved = resolveSuggestion(_suggestion([_binaryTarget("lamp", true)]),
          typesByDevice: {"lamp": _lampType()}, functions: _functions, names: _names);
      expect(resolved.offersAutoOff, isFalse);
      expect(acceptVariables(resolved)["auto_off_s"], "");
      expect(() => acceptVariablesFor(resolved, 120), throwsArgumentError);
    });

    test("a false target alone does not make the switch-off available", () {
      final resolved = resolveSuggestion(_suggestion([_binaryTarget("lamp", false)], autoOffS: 120),
          typesByDevice: {"lamp": _lampType()}, functions: _functions, names: _names);
      expect(resolved.canAutoOff, isFalse);
      expect(resolved.offersAutoOff, isFalse);
    });

    test("with one switchable and one on-only target the switch-off is offered and only the switchable one carries off fields", () {
      final resolved = resolveSuggestion(
          _suggestion([_binaryTarget("lamp", true), _binaryTarget("plug", true)], autoOffS: 120),
          typesByDevice: {"lamp": _lampType(), "plug": onOnlyType()},
          functions: _functions,
          names: _names);
      expect(resolved.offersAutoOff, isTrue);
      final targets = json.decode(acceptVariablesFor(resolved, 60)["targets"]!) as List<dynamic>;
      final byDevice = {for (final t in targets) (t as Map<String, dynamic>)["device_id"] as String: t};
      expect(byDevice["lamp"]!["off_function_id"], setDeviceOffFunctionId);
      expect(byDevice["plug"]!["off_function_id"], isNull);
      expect(byDevice["plug"]!["function_id"], setDeviceOnFunctionId);
    });

    test("the bounds 5 and 3600 seconds are accepted, the values just outside them are refused", () {
      final resolved = resolveSuggestion(_suggestion([_binaryTarget("lamp", true)], autoOffS: 120),
          typesByDevice: {"lamp": _lampType()}, functions: _functions, names: _names);
      expect(acceptVariablesFor(resolved, autoOffMinSeconds)["auto_off_s"], "5");
      expect(acceptVariablesFor(resolved, autoOffMaxSeconds)["auto_off_s"], "3600");
      expect(() => acceptVariablesFor(resolved, 4), throwsArgumentError);
      expect(() => acceptVariablesFor(resolved, 3601), throwsArgumentError);
      expect(() => acceptVariablesFor(resolved, 0), throwsArgumentError);
    });

    test("parseAutoOffSeconds takes whole seconds within the bounds and nothing else", () {
      expect(parseAutoOffSeconds("5"), 5);
      expect(parseAutoOffSeconds(" 180 "), 180);
      expect(parseAutoOffSeconds("3600"), 3600);
      expect(parseAutoOffSeconds("4"), isNull);
      expect(parseAutoOffSeconds("3601"), isNull);
      expect(parseAutoOffSeconds("2.5"), isNull);
      expect(parseAutoOffSeconds("-5"), isNull);
      expect(parseAutoOffSeconds("1e3"), isNull);
      expect(parseAutoOffSeconds(""), isNull);
    });
  });

  group("accepted modules and keys", () {
    test("the suggestion id of each suggestion-keyed module is mapped to its module", () {
      final modules = [
        AutomationModule("m-1", ["suggestion:s-1"]),
        AutomationModule("m-2", ["other", "suggestion:s-2"]),
        AutomationModule("m-3", ["unrelated"]),
      ];
      expect(acceptedModules(modules), {"s-1": "m-1", "s-2": "m-2"});
    });

    test("keys are built from the suggestion id", () {
      expect(suggestionKey("s-1"), "suggestion:s-1");
      expect(dismissKey("s-1"), "automation-suggester.dismissed.s-1");
    });

    test("a module listing item parses its id and keys", () {
      final m = AutomationModule.fromJson({"id": "m-1", "keys": ["suggestion:s-1"], "module_type": "process_deployment"});
      expect(m.id, "m-1");
      expect(m.keys, ["suggestion:s-1"]);
    });

    test("the module data of a listing item is kept, a non-object one is not", () {
      final m = AutomationModule.fromJson({
        "id": "m-1",
        "keys": ["suggestion:s-1"],
        "module_data": {"auto_off_s": 120},
      });
      expect(m.moduleData, {"auto_off_s": 120});
      expect(AutomationModule.fromJson({"id": "m-2", "keys": [], "module_data": "x"}).moduleData, isNull);
      expect(AutomationModule.fromJson({"id": "m-3", "keys": []}).moduleData, isNull);
    });
  });

  group("auto-off of accepted modules", () {
    test("a number is the seconds the module carries", () {
      final off = moduleAutoOff(AutomationModule("m", [], moduleData: {"auto_off_s": 120}));
      expect(off.seconds, 120);
      expect(off.known, isTrue);
    });

    test("an explicit null means no auto-off, and that is known", () {
      final off = moduleAutoOff(AutomationModule("m", [], moduleData: {"auto_off_s": null}));
      expect(off.seconds, isNull);
      expect(off.known, isTrue);
    });

    test("a module without the field, or without module data, is unknown", () {
      final missing = moduleAutoOff(AutomationModule("m", [], moduleData: {"suggestion_id": "s-1"}));
      expect(missing.seconds, isNull);
      expect(missing.known, isFalse);
      final noData = moduleAutoOff(AutomationModule("m", []));
      expect(noData.known, isFalse);
    });

    test("a value that is neither a number nor null is unknown, not no auto-off", () {
      final off = moduleAutoOff(AutomationModule("m", [], moduleData: {"auto_off_s": "120"}));
      expect(off.seconds, isNull);
      expect(off.known, isFalse);
    });
  });

  group("open and dismissed split", () {
    ResolvedSuggestion resolvedOf(String id, {bool withTarget = true}) {
      final s = Suggestion(
        id,
        SuggestionTrigger("plug", "svc-plug", "value.state", "binary", "on", "off"),
        SuggestionWindow("19:00", "02:00", const [0, 1, 2, 3, 4, 5, 6], "Europe/Berlin"),
        const [],
        null,
        SuggestionStats(291, 90, 0.31),
      );
      final targets = withTarget
          ? [ResolvedTarget("lamp", "svc-switch", setDeviceOnFunctionId, "ch-bool", true, null, null, null, null)]
          : <ResolvedTarget>[];
      return ResolvedSuggestion(s, targets, "Stehlampe aus → Licht EG an");
    }

    test("an open and a dismissed suggestion land in their lists, the rest in neither", () {
      final candidates = [
        resolvedOf("open").suggestion,
        resolvedOf("gone").suggestion,
        resolvedOf("unresolved").suggestion,
        resolvedOf("no-target").suggestion,
        resolvedOf("accepted").suggestion,
        resolvedOf("open-no-target").suggestion,
      ];
      final resolvedById = {
        for (final id in ["open", "gone", "no-target", "accepted"]) id: resolvedOf(id, withTarget: id != "no-target"),
        "open-no-target": resolvedOf("open-no-target", withTarget: false),
      };
      final split = splitSuggestions(
        candidates: candidates,
        accepted: {"accepted"},
        dismissed: {"gone", "unresolved", "no-target", "accepted"},
        resolvedById: resolvedById,
      );
      expect([for (final r in split.open) r.id], ["open"]);
      expect([for (final r in split.dismissed) r.id], ["gone"]);
    });

    test("a dismissed suggestion without a resolved target is not offered for restore", () {
      final split = splitSuggestions(
        candidates: [resolvedOf("gone").suggestion],
        accepted: const {},
        dismissed: {"gone"},
        resolvedById: {"gone": resolvedOf("gone", withTarget: false)},
      );
      expect(split.dismissed, isEmpty);
      expect(split.open, isEmpty);
    });
  });

  group("edit payload", () {
    test("an edit with a duration carries the off part, one without carries none", () {
      final resolved = resolveSuggestion(_suggestion([_binaryTarget("lamp", true)], autoOffS: 120),
          typesByDevice: {"lamp": _lampType()}, functions: _functions, names: _names);
      final withOff = acceptVariablesFor(resolved, 180);
      expect(withOff["suggestion_id"], "s-1");
      expect(withOff["auto_off_s"], "180");
      final target = (json.decode(withOff["targets"]!) as List<dynamic>).single as Map<String, dynamic>;
      expect(target["off_function_id"], setDeviceOffFunctionId);

      final withoutOff = acceptVariablesFor(resolved, null);
      expect(withoutOff["suggestion_id"], "s-1");
      expect(withoutOff["auto_off_s"], "");
      final plain = (json.decode(withoutOff["targets"]!) as List<dynamic>).single as Map<String, dynamic>;
      expect(plain["off_function_id"], isNull);
      expect(plain["off_value"], isNull);
    });
  });

  test("an export without its first row counts as no list yet, other failures do not", () {
    const missing = 'ERROR: relation "userid:x_export:y" does not exist (SQLSTATE 42P01)\nbad request';
    expect(exportHasNoTable(400, missing), isTrue);
    expect(exportHasNoTable(400, "bad request"), isFalse);
    expect(exportHasNoTable(500, missing), isFalse);
    expect(exportHasNoTable(null, null), isFalse);
  });
}
