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

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/aspect.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/function.dart';
import 'package:mobile_app/widgets/tabs/groups/group_edit_devices.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

// Rows as device-repository generates them for a device whose variable carries
// [a, b]: one per single aspect and one for the combination. The last row is
// in the shape stored before aspect lists and has to stay without the key.
final _helperCriteria = [
  {"aspect_id": "a", "aspect_ids": ["a"], "device_class_id": "c", "function_id": "f", "interaction": "request"},
  {"aspect_id": "b", "aspect_ids": ["b"], "device_class_id": "c", "function_id": "f", "interaction": "request"},
  {"aspect_id": "a", "aspect_ids": ["a", "b"], "device_class_id": "c", "function_id": "f", "interaction": "request"},
  {"aspect_id": "x", "device_class_id": "c", "function_id": "f", "interaction": "event"},
];

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  group("DeviceGroupCriteria JSON", () {
    test("keeps aspect_ids through a round trip", () {
      for (final row in _helperCriteria) {
        final json = jsonDecode(jsonEncode(DeviceGroupCriteria.fromJson(row).toJson()));
        expect(json, row);
      }
    });

    test("a row read without aspect_ids is written without the key", () {
      final json = DeviceGroupCriteria.fromJson(_helperCriteria.last).toJson();
      expect(json.containsKey("aspect_ids"), isFalse);
    });
  });

  testWidgets("saving an edited group sends the multi-aspect rows unchanged", (tester) async {
    final backend = FakeBackend();
    backend.serveJson("POST", "/device-selection/device-group-helper", 200, {
      "options": [
        {"device": deviceJson("device-1", "Living room sensor"), "removes_criteria": []},
      ],
      "criteria": _helperCriteria,
    });
    final savedJson = {
      "id": "group-1",
      "name": "Ground floor",
      "image": "",
      "criteria": _helperCriteria,
      "device_ids": <String>[],
      "attributes": null,
    };
    backend.serveJson("PUT", "/device-manager/device-groups/group-1", 200, savedJson);
    serveGoldenBackend(backend);

    final group = DeviceGroup("group-1", "Ground floor", null, "", [], null);
    await pumpGolden(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GroupEditDevices(group))),
          child: const Text("open"),
        ),
      ),
      dark: false,
    );
    await tester.tap(find.text("open"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("Living room sensor"), findsOneWidget);

    await tester.tap(find.text("Save"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(backend.requests.where((r) => r.method == "GET" && r.uri.path == "/device-repository/device-groups/group-1"),
        isEmpty,
        reason: "a group not read from a stale cache is saved without refetching it");
    final puts = backend.requests.where((r) => r.method == "PUT").toList();
    expect(puts, hasLength(1));
    final body = jsonDecode(puts.single.data as String) as Map<String, dynamic>;
    expect(body["criteria"], _helperCriteria);
  });

  group("DeviceGroup.prepareStates", () {
    setUp(() {
      AppState().platformFunctions["f"] = PlatformFunction("f", "f", "concept", "F");
    });

    DeviceGroup groupWith(List<Map<String, dynamic>> criteria) => DeviceGroup(
        "group-1", "Ground floor", criteria.map(DeviceGroupCriteria.fromJson).toList(), "", [], null);

    test("a combination row yields its own state next to the single rows", () {
      final group = groupWith(_helperCriteria.take(3).toList());
      group.prepareStates();

      expect(group.states.map((s) => s.aspectIds), [
        ["a"],
        ["b"],
        ["a", "b"],
      ]);
      expect(group.states.map((s) => s.aspectId), ["a", "b", "a"]);
    });

    test("rows naming the same aspect set in another order or spelling share one state", () {
      final group = groupWith([
        {"aspect_id": "a", "device_class_id": "c", "function_id": "f", "interaction": "request"},
        {"aspect_id": "a", "aspect_ids": ["a"], "device_class_id": "c", "function_id": "f", "interaction": "event"},
        {"aspect_id": "a", "aspect_ids": ["b", "a"], "device_class_id": "c", "function_id": "f", "interaction": "request"},
        {"aspect_id": "a", "aspect_ids": ["a", "b"], "device_class_id": "c", "function_id": "f", "interaction": "event"},
      ]);
      group.prepareStates();

      expect(group.states.map((s) => s.aspectIds), [
        ["a"],
        ["a", "b"],
      ]);
    });

    test("single-aspect rows keep one state per aspect and device class", () {
      final group = groupWith([
        {"aspect_id": "a", "device_class_id": "c", "function_id": "f", "interaction": "request"},
        {"aspect_id": "a", "device_class_id": "d", "function_id": "f", "interaction": "request"},
        {"aspect_id": "", "device_class_id": "c", "function_id": "f", "interaction": "request"},
      ]);
      group.prepareStates();

      expect(group.states.map((s) => [s.aspectId, s.deviceClassId]), [
        ["a", "c"],
        ["a", "d"],
        [null, "c"],
      ]);
    });
  });

  group("DeviceGroup.shownStates", () {
    const setOn = "$controllingFunctionPrefix:set-on";
    setUp(() {
      AppState().platformFunctions["f"] = PlatformFunction("f", "f", "concept", "F");
      AppState().platformFunctions[setOn] = PlatformFunction(setOn, setOn, "concept", "Switch on");
      for (final a in [
        Aspect("air", "Air", [Aspect("inside", "Inside", null)]),
        Aspect("device", "Device", null),
        Aspect("lighting", "Lighting", null),
      ]) {
        AppState().aspects[a.id] = a;
      }
    });

    Map<String, dynamic> row(String functionId, List<String> aspectIds, {String deviceClassId = ""}) => {
          "aspect_id": aspectIds.isEmpty ? "" : ([...aspectIds]..sort()).first,
          if (aspectIds.isNotEmpty) "aspect_ids": aspectIds,
          "device_class_id": deviceClassId,
          "function_id": functionId,
          "interaction": "request",
        };

    List<List<String>> shown(List<Map<String, dynamic>> criteria) {
      final group = DeviceGroup("group-1", "Living room lamps", criteria.map(DeviceGroupCriteria.fromJson).toList(), "", [], null)
        ..prepareStates();
      return group.shownStates.map((s) => [s.functionId, ...s.aspectIds]).toList();
    }

    test("the subsets of a combination are left out, per function", () {
      expect(
          shown([
            row("f", ["device", "lighting"]),
            row("f", ["device"]),
            row("f", ["lighting"]),
            row(setOn, ["device", "lighting"]),
            row(setOn, ["device"]),
            row(setOn, ["lighting"]),
          ]),
          [
            ["f", "device", "lighting"],
            [setOn, "device", "lighting"],
          ]);
    });

    test("an ancestor aspect is left out next to its descendant", () {
      expect(shown([row("f", ["air"]), row("f", ["inside"])]), [
        ["f", "inside"],
      ]);
    });

    test("unrelated aspects, rows without aspects and other device classes stay", () {
      expect(
          shown([
            row(setOn, ["device"]),
            row(setOn, ["lighting"]),
            row("f", [], deviceClassId: "class-lamp"),
            row("f", ["device"], deviceClassId: "class-lamp"),
            row("f", ["device", "lighting"]),
          ]),
          [
            [setOn, "device"],
            [setOn, "lighting"],
            ["f"],
            ["f", "device"],
            ["f", "device", "lighting"],
          ]);
    });

    test("a control on a device class is left out next to controls of its function on aspects", () {
      expect(
          shown([
            row(setOn, [], deviceClassId: "class-thermostat"),
            row(setOn, ["device"]),
            row("f", [], deviceClassId: "class-thermostat"),
          ]),
          [
            [setOn, "device"],
            ["f"],
          ]);
      expect(shown([row(setOn, [], deviceClassId: "class-thermostat")]), [
        [setOn],
      ]);
    });
  });
}
