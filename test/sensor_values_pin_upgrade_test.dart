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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/content.dart';
import 'package:mobile_app/models/content_variable.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/models/function.dart';
import 'package:mobile_app/models/sensor_pin.dart';
import 'package:mobile_app/models/sensor_tab.dart';
import 'package:mobile_app/models/service.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/widgets/tabs/sensors/sensor_values.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

ContentVariable _temperature(String name, List<String> aspectIds) => ContentVariable(
    "cv-$name", name, null, null, aspectIds.first, "function-1", "https://schema.org/Float", null, null, null, aspectIds);

DeviceType _deviceType(String id) {
  final service = Service("service-1", "local-service-1", "Service 1", "", "protocol-1", "event", "group-1", null, [
    Content("content-1", "json", "segment-1", ContentVariable("root", "root", null, null, null, null,
        "https://schema.org/StructuredValue", [_temperature("inside", ["air", "inside"]), _temperature("outside", ["air", "outside"])], null, null)),
  ]);
  return DeviceType(id, "Type", "", "class-1", [service], null);
}

DeviceGroup _group(String id, {required bool stale}) {
  final group = DeviceGroup(id, "Group $id", [
    DeviceGroupCriteria.fromJson({"aspect_id": "a", "aspect_ids": ["a"], "device_class_id": "c", "function_id": "function-1", "interaction": "request"}),
    DeviceGroupCriteria.fromJson({"aspect_id": "a", "aspect_ids": ["a", "b"], "device_class_id": "c", "function_id": "function-1", "interaction": "request"}),
  ], "", [], null);
  group.criteriaMayPredateAspectLists = stale;
  return group;
}

SensorPin _devicePin(String deviceId, String aspectId, String alias) =>
    SensorPin(deviceId: deviceId, functionId: "function-1", aspectId: aspectId, serviceGroupKey: "group-1", alias: alias);

SensorPin _groupPin(String groupId, String alias) =>
    SensorPin(groupId: groupId, deviceClassId: "c", functionId: "function-1", aspectId: "a", alias: alias);

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  // A tab save awaits a Hive write, whose file operations only complete on the
  // real event loop, each step continuing in the next pump.
  Future<void> saveCompletes(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await settle(tester);
  }

  List<SensorPin> stored() => Settings.getSensorTabs().single.pins;

  // One testWidgets for the whole sequence: Dio instances are memoized per
  // process, see docs/testing.md.
  testWidgets("old pins are upgraded in memory, saved with the next edit, and stay editable", (tester) async {
    final backend = FakeBackend();
    backend.serveJson("GET", "/device-repository/extended-devices", 200, [
      deviceJson("device-1", "Weather station", deviceTypeId: "type-1"),
      deviceJson("device-2", "Greenhouse", deviceTypeId: "type-2"),
    ]);
    backend.serveJson("GET", "/device-repository/device-types", 200, []);
    backend.serveJson("GET", "/device-repository/user-device-types", 200, []);
    // Values do not matter here; a failed batch leaves them empty.
    backend.serveJson("POST", "/device-command/commands/batch", 500, "boom");
    backend.serveJson("POST", "/db/v3/queries", 200, [[]]);
    serveGoldenBackend(backend);
    await warmUpMgwStorage(tester);

    AppState().platformFunctions["function-1"] = PlatformFunction("function-1", "temperature", "concept-1", "Temperature");
    AppState().deviceGroups
      ..add(_group("stale", stale: true))
      ..add(_group("fresh", stale: false));

    final tab = SensorTab(id: "tab-1", name: "Weather", pins: [
      _devicePin("device-1", "outside", "Outdoors"),
      _devicePin("device-1", "air", "Ambiguous"),
      _devicePin("device-2", "inside", "Indoors"),
      _groupPin("stale", "Stale group"),
      _groupPin("fresh", "Fresh group"),
      // The same value added again after the app update, in the new format.
      const SensorPin(groupId: "fresh", deviceClassId: "c", functionId: "function-1", aspectId: "a", aspectIds: ["a"],
          alias: "Fresh again"),
    ]);
    await tester.runAsync(() => Settings.setSensorTabs([tab]));

    // Neither device type is known yet, so only the group pins can resolve.
    await pumpGolden(tester, const Scaffold(body: SensorValues()), dark: false);
    await settle(tester);
    expect(stored().map((p) => [p.alias, p.aspectIds]), tab.pins.map((p) => [p.alias, p.aspectIds]),
        reason: "the upgrade alone writes nothing");

    // Remove a pin whose card was opened before its upgrade.
    await tester.longPress(find.text("Outdoors"));
    await settle(tester);
    await tester.tap(find.text("Remove value"));
    await settle(tester);
    AppState().deviceTypes["type-1"] = _deviceType("type-1");
    AppState().pushRefresh();
    await settle(tester);
    await tester.tap(find.text("Remove"));
    await saveCompletes(tester);

    expect(find.text("Outdoors"), findsNothing);
    var pins = stored();
    expect(pins.map((p) => p.alias), ["Ambiguous", "Indoors", "Stale group", "Fresh group"]);
    expect(pins[0].aspectIds, isNull, reason: "air fits both values of the weather station");
    expect(pins[1].aspectIds, isNull, reason: "the greenhouse's type is still unknown");
    expect(pins[2].aspectIds, isNull, reason: "the group's cached criteria may predate aspect lists");
    expect(pins[3].aspectIds, ["a"], reason: "the upgrade is saved with the removal, its duplicate dropped");

    // Edit a pin whose dialog was opened before its upgrade.
    await tester.longPress(find.text("Indoors"));
    await settle(tester);
    await tester.tap(find.text("Edit title / subtitle / icon"));
    await settle(tester);
    AppState().deviceTypes["type-2"] = _deviceType("type-2");
    AppState().pushRefresh();
    await settle(tester);
    await tester.enterText(find.byType(TextFormField).first, "Greenhouse air");
    await tester.tap(find.text("Save"));
    await saveCompletes(tester);

    pins = stored();
    expect(pins.map((p) => p.alias), ["Ambiguous", "Greenhouse air", "Stale group", "Fresh group"]);
    expect(pins[1].aspectIds, ["air", "inside"]);
    expect(
        pins[1],
        const SensorPin(
            deviceId: "device-2",
            functionId: "function-1",
            aspectId: "air",
            aspectIds: ["air", "inside"],
            serviceGroupKey: "group-1"),
        reason: "equal to a new pin of that value, so picking it again reads as already added");
  });
}
