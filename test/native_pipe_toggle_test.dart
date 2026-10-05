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
import "package:mobile_app/models/device_state.dart";
import "package:mobile_app/models/function.dart";
import "package:mobile_app/native_pipe.dart";

import "golden_helper.dart";

const _get = "urn:infai:ses:measuring-function:on-off";
const _on = "urn:infai:ses:controlling-function:on";

DeviceState _state(String functionId, List<String> aspectIds, String serviceId, String path) => DeviceState(
    true, serviceId, "group-1", functionId, null, functionId == _on, null, null, "device-1", path, null,
    aspectIds: aspectIds);

/// The entry the platform side sends back for [reading]: its own fields only,
/// so the aspect list is gone and only the first aspect is left.
DeviceState _platformEntry(DeviceState reading) {
  final json = jsonDecode(jsonEncode(reading.toJson())) as Map<String, dynamic>;
  json.remove("aspectIds");
  return DeviceState.fromJson(json);
}

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  setUp(() {
    AppState().platformFunctions[_get] = PlatformFunction(_get, "on-off", "concept-on-off", "Power");
    AppState().platformFunctions[_on] = PlatformFunction(_on, "on", "concept-on-off", "On");
  });

  tearDown(resetAppStateForGolden);

  group("NativePipe.controlsForToggle", () {
    test("service and path pick the reading the entry was made for", () {
      final single = _state(_get, ["a"], "s1", "single");
      final combined = _state(_get, ["a", "b"], "s2", "combined");
      final singleInput = _state(_on, ["a"], "s1", "single-in");
      final combinedInput = _state(_on, ["a", "b"], "s2", "combined-in");
      final states = [single, combined, singleInput, combinedInput];

      expect(NativePipe.controlsForToggle(_platformEntry(combined), null, states, _on), [same(combinedInput)]);
      expect(NativePipe.controlsForToggle(_platformEntry(single), null, states, _on), [same(singleInput)]);
    });

    test("a found reading pairs as on the detail page, not by its first aspect", () {
      final ab = _state(_get, ["a", "b"], "s1", "ab");
      final ac = _state(_get, ["a", "c"], "s1", "ac");
      final input = _state(_on, ["a"], "s1", "in");

      expect(NativePipe.controlsForToggle(_platformEntry(ab), null, [ab, ac, input], _on), isEmpty,
          reason: "the input on fewer aspects than both readings picks neither");
      expect(NativePipe.controlsForToggle(_platformEntry(ab), null, [ab, input], _on), [same(input)]);
      final reading = _state(_get, ["a"], "s1", "reading");
      final states = [reading, _state(_on, ["a", "b"], "s2", "in-b"), _state(_on, ["a", "c"], "s3", "in-c")];
      expect(NativePipe.controlsForToggle(_platformEntry(reading), null, states, _on), isEmpty,
          reason: "controls on more aspects than the reading do not pair");
    });

    test("an entry without a reading fires the first control sharing its first aspect, as before", () {
      final first = _state(_on, ["a", "b"], "s2", "in-b");
      final entry = DeviceState(true, "s-old", "group-1", _get, "a", false, null, null, "device-1", "old", null);

      expect(NativePipe.controlsForToggle(entry, null, [first, _state(_on, ["a", "c"], "s3", "in-c")], _on),
          [same(first)]);
    });

    test("an entry whose service is gone does not borrow another reading's aspects", () {
      final reading = _state(_get, ["a", "b"], "s1", "moved");
      final entry = DeviceState(true, "s-old", "group-1", _get, "b", false, null, null, "device-1", "old", null);

      expect(NativePipe.controlsForToggle(entry, null, [reading, _state(_on, ["a", "b"], "s1", "in")], _on), isEmpty,
          reason: "before aspect lists no control with first aspect b existed, and the toggle failed");
      final single = _state(_on, ["b"], "s1", "in-b");
      expect(NativePipe.controlsForToggle(entry, null, [reading, _state(_on, ["a", "b"], "s1", "in"), single], _on),
          [same(single)]);
    });

    test("an entry whose reading is gone and ambiguous picks the control by its aspect, as before", () {
      final ab = _state(_get, ["a", "b"], "s1", "ab");
      final ac = _state(_get, ["a", "c"], "s2", "ac");
      final input = _state(_on, ["a"], "s3", "in");
      final entry = DeviceState(true, "s-old", "group-1", _get, "a", false, null, null, "device-1", "old", null);

      expect(NativePipe.controlsForToggle(entry, null, [ab, ac, input], _on), [same(input)]);
    });
  });
}
