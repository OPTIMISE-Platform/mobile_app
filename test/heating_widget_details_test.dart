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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/models/device_command_response.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/base.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/heating_schedule.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/shared/widget_info.dart';
import 'package:mobile_app/widgets/tabs/smart-services/heating_schedule_model.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

Map<String, dynamic> _variable(String name, String function, List<String> aspects, {List<Map<String, dynamic>>? subs}) => {
      "id": name,
      "name": name,
      "type": subs == null ? "https://schema.org/Float" : "https://schema.org/StructuredValue",
      "function_id": function,
      "aspect_ids": aspects,
      "sub_content_variables": subs,
    };

Map<String, dynamic> _service(String id, List<Map<String, dynamic>> outputs) => {
      "id": id,
      "local_id": id,
      "name": id,
      "description": "",
      "protocol_id": "p",
      "interaction": "event",
      "service_group_key": "",
      "outputs": [
        for (final o in outputs) {"id": "c", "serialization": "json", "protocol_segment_id": "s", "content_variable": o}
      ],
    };

DeviceType _type(List<Map<String, dynamic>> services) => DeviceType.fromJson({
      "id": "type-1",
      "name": "t",
      "description": "",
      "device_class_id": "c",
      "services": services,
    });

// 2025-01-06 is a Monday, Berlin is UTC+1 in January.
DateTime _berlin(int day, int hour, int minute) => DateTime.utc(2025, 1, day, hour - 1, minute);

const _office = HeatingSchedule([HeatingWindow([0, 1, 2, 3, 4], 360, 1200, 21)], 17);

void main() {
  group("value sources", () {
    test("room and set point share the function and are told apart by the aspect", () {
      final type = _type([
        _service("setpoint", [_variable("t", heatingRoomFunctionId, [heatingTargetAspectId])]),
        _service("measured", [_variable("t", heatingRoomFunctionId, [heatingAirAspectId, heatingReadingAspectId])]),
      ]);
      expect(findHeatingValueSource(type, HeatingValueKind.room)?.serviceId, "measured");
      expect(findHeatingValueSource(type, HeatingValueKind.target)?.serviceId, "setpoint");
      expect(findHeatingValueSource(type, HeatingValueKind.battery), isNull);
    });

    test("a set point listed before the room reading does not shadow it", () {
      const indoor = "urn:infai:ses:aspect:indoor";
      final type = _type([
        _service("get", [
          _variable("setpoint", heatingRoomFunctionId, [heatingTargetAspectId, heatingAirAspectId, indoor]),
          _variable("room", heatingRoomFunctionId, [heatingAirAspectId, indoor, heatingReadingAspectId]),
        ]),
      ]);
      final room = findHeatingValueSource(type, HeatingValueKind.room)!;
      expect(room.serviceId, "get");
      expect(room.aspectIds, [heatingAirAspectId, heatingReadingAspectId]);
      final device = DeviceInstance.fromJson({
        "id": "d", "local_id": "d", "name": "d", "attributes": [], "device_type_id": "type-1", "shared": false,
        "owner_id": "u", "display_name": "d", "connection_state": "online",
      });
      expect(room.toCommand(device).aspect_ids, [heatingAirAspectId, heatingReadingAspectId]);
      expect(findHeatingValueSource(type, HeatingValueKind.target)!.toCommand(device).aspect_ids, [heatingTargetAspectId]);
    });

    test("a variable nested in a structure is found, and the battery takes any aspect", () {
      final type = _type([
        _service("state", [
          _variable("root", "", [], subs: [_variable("battery", heatingBatteryFunctionId, ["urn:infai:ses:aspect:device"])])
        ]),
      ]);
      final source = findHeatingValueSource(type, HeatingValueKind.battery)!;
      expect(source.serviceId, "state");
      expect(source.aspectId, "urn:infai:ses:aspect:device");
      expect(findHeatingValueSource(type, HeatingValueKind.room), isNull);
    });
  });

  group("answers", () {
    test("a non-200 answer and a non-numeric value stay unavailable", () {
      final values = heatingValuesFromAnswers([
        ("a", HeatingValueKind.room),
        ("a", HeatingValueKind.target),
        ("a", HeatingValueKind.battery),
        ("b", HeatingValueKind.room),
      ], [
        DeviceCommandResponse(200, 21.5),
        DeviceCommandResponse(200, "warm"),
        DeviceCommandResponse(502, 80),
        DeviceCommandResponse(200, "19"),
      ]);
      expect(values["a"]!.room, 21.5);
      expect(values["a"]!.target, isNull);
      expect(values["a"]!.battery, isNull);
      expect(values["b"]!.room, 19);
    });

    test("mean of the room temperatures present, one decimal", () {
      expect(heatingMeanRoom([21, null, 22.2]), 21.6);
      expect(heatingMeanRoom([21, 22, 22]), 21.7);
      expect(heatingMeanRoom([null, null]), isNull);
      expect(heatingMeanRoom([]), isNull);
    });

    test("batteries at or below 20 percent are named, others are not", () {
      const a = HeatingThermostat("a", "Window"), b = HeatingThermostat("b", "Door"), c = HeatingThermostat("c", "Desk");
      final low = heatingLowBatteries([a, b, c],
          {"a": const HeatingDeviceValues(battery: 12), "b": const HeatingDeviceValues(battery: 20.5), "c": const HeatingDeviceValues(room: 20)});
      expect(low.map((e) => (e.$1.label, e.$2)), [("Window", 12.0)]);
      expect(heatingLowBatteries([b], {"b": const HeatingDeviceValues(battery: 20)}), hasLength(1));
    });
  });

  group("last switch", () {
    test("is the start of the current window or the end of the last one", () {
      expect(_office.lastSwitch(_berlin(6, 12, 0))?.at, _berlin(6, 6, 0));
      expect(_office.lastSwitch(_berlin(6, 21, 0))?.at, _berlin(6, 20, 0));
      // Monday 05:00 lies before the first window: the last switch was Friday evening
      expect(_office.lastSwitch(_berlin(6, 5, 0))?.at, DateTime.utc(2025, 1, 3, 19, 0));
    });

    test("a switch at this very minute counts, and a constant plan has none", () {
      expect(_office.lastSwitch(_berlin(6, 6, 0))?.at, _berlin(6, 6, 0));
      expect(const HeatingSchedule([], 17).lastSwitch(_berlin(6, 12, 0)), isNull);
    });
  });

  group("manual override", () {
    test("needs a set point 0.5 off the plan", () {
      final now = _berlin(6, 12, 0);
      expect(heatingManualOverride(_office, [21.4, 20.6], now), isNull);
      expect(heatingManualOverride(_office, [21.5], now)?.temperature, 21.5);
      expect(heatingManualOverride(_office, [20.5], now)?.temperature, 20.5);
      // 22.8 - 22.3 is 0.4999999 in binary floating point
      const sched = HeatingSchedule([HeatingWindow([], 0, 0, 22.3)], 17);
      expect(heatingManualOverride(sched, [22.8], now)?.temperature, 22.8);
    });

    test("waits ten minutes after a switch for the device to report", () {
      expect(heatingManualOverride(_office, [25], _berlin(6, 6, 10)), isNull);
      expect(heatingManualOverride(_office, [25], _berlin(6, 6, 11)), isNotNull);
    });

    test("several different set points give no temperature; the end is the next switch", () {
      final o = heatingManualOverride(_office, [25, 23], _berlin(6, 12, 0))!;
      expect(o.temperature, isNull);
      expect(o.until, _berlin(6, 20, 0));
      expect(heatingManualOverride(const HeatingSchedule([], 17), [25], _berlin(6, 12, 0))!.until, isNull);
    });
  });

  group("countdown", () {
    test("hours and minutes, minutes, under a minute", () {
      expect(heatingCountdown(const Duration(hours: 3, minutes: 10, seconds: 40)), "in 3 h 10 min");
      expect(heatingCountdown(const Duration(hours: 2)), "in 2 h");
      expect(heatingCountdown(const Duration(minutes: 25)), "in 25 min");
      expect(heatingCountdown(const Duration(minutes: 59, seconds: 59)), "in 59 min");
      expect(heatingCountdown(const Duration(minutes: 60)), "in 1 h");
      expect(heatingCountdown(const Duration(seconds: 59)), "in under a minute");
    });

    test("more than a day ahead has none", () {
      expect(heatingCountdown(const Duration(hours: 24)), "in 24 h");
      expect(heatingCountdown(const Duration(hours: 24, seconds: 1)), isNull);
    });
  });

  group("colour scale", () {
    test("is blue up to 16 degrees, orange from 22 and linear between", () {
      expect(heatingTemperatureColor(5), heatingColdColor);
      expect(heatingTemperatureColor(16), heatingColdColor);
      expect(heatingTemperatureColor(22), heatingWarmColor);
      expect(heatingTemperatureColor(30), heatingWarmColor);
      expect(heatingTemperatureColor(19), Color.lerp(heatingColdColor, heatingWarmColor, 0.5));
    });
  });

  group("widget", () {
    const repo = "/smart-services/repository";
    const ct = "urn:infai:ses:device:ct";
    final thermostats = json.encode([
      json.encode({"device_selection": {"device_id": ct, "service_id": null, "path": null}, "label": "Window"}),
    ]);

    Map<String, dynamic> instance({String? error, bool ready = true}) => {
          "description": "",
          "design_id": "d",
          "id": "inst-1",
          "name": "Heating",
          "release_id": "rel-1",
          "user_id": "u",
          "error": error,
          "ready": ready,
          "deleting": false,
          "new_release_id": null,
          "parameters": [
            {"id": "thermostats", "label": "T", "value": thermostats, "value_label": null},
            {"id": "schedule", "label": "S", "value": '{"windows":[{"weekdays":[],"from":"00:00","to":"00:00","temperature":21}]}', "value_label": null},
            {"id": "setback", "label": "B", "value": 17, "value_label": null},
          ],
        };

    setUpAll(() async {
      await setUpGoldenEnvironment();
    });

    late FakeBackend backend;
    setUp(() {
      backend = FakeBackend();
      backend.serveJson("GET", "$repo/instances/inst-1", 200, instance());
      backend.serveJson("GET", "/device-repository/extended-devices", 200, [
        {
          "id": ct,
          "local_id": "ct",
          "name": "Window",
          "attributes": [],
          "device_type_id": "type-1",
          "shared": false,
          "owner_id": "u",
          "display_name": "Window",
          "connection_state": "online",
        }
      ]);
      backend.serveJson("GET", "/device-repository/device-types", 200, [
        _type([
          _service("s", [
            _variable("room", heatingRoomFunctionId, [heatingAirAspectId, heatingReadingAspectId]),
            _variable("target", heatingRoomFunctionId, [heatingTargetAspectId]),
            _variable("battery", heatingBatteryFunctionId, ["urn:infai:ses:aspect:device"]),
          ])
        ]).toJson()
      ]);
      backend.serveJson("POST", "/device-command/commands/batch", 200, [
        {"status_code": 200, "message": 19.5},
        {"status_code": 200, "message": 24},
        {"status_code": 200, "message": 12},
      ]);
      serveGoldenBackend(backend);
    });

    tearDown(resetGoldenBackend);

    Future<SmSeHeatingSchedule> refreshed() async {
      final w = SmSeHeatingSchedule()
        ..id = "heating_schedule"
        ..instance_id = "inst-1"
        ..widgetInfo = WidgetInfo.fromJson({"widget_type": smSeHeatingScheduleType, "widget_data": {}});
      await w.refresh();
      return w;
    }

    Future<void> mount(WidgetTester tester, SmSeHeatingSchedule w) async {
      tester.view.physicalSize = const Size(412, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (context) => w.build(context, false)))));
    }

    // One test, one load: later loads in the same file may never get their answers (docs/testing.md).
    test("the batch asks for the three values in Celsius and percent", () async {
      final w = await refreshed();
      final sent = (json.decode(backend.requests.singleWhere((r) => r.method == "POST").data as String) as List).cast<Map<String, dynamic>>();
      expect(sent.map((c) => c["aspect_id"]), [heatingAirAspectId, heatingTargetAspectId, "urn:infai:ses:aspect:device"]);
      expect(sent.map((c) => c["characteristic_id"]),
          [heatingCelsiusCharacteristicId, heatingCelsiusCharacteristicId, heatingPercentCharacteristicId]);
      expect(sent.every((c) => c["device_id"] == ct && c["service_id"] == "s"), isTrue);
      expect(backend.requests.singleWhere((r) => r.method == "POST").uri.queryParameters["prefer_event_value"], "true");
      expect(w.height, 13 + 1 + 1); // legacy plan: week open, battery line, manual pill
    });

    testWidgets("measured temperature, target, battery, manual pill, status and week toggle", (tester) async {
      final w = await tester.runAsync(refreshed) as SmSeHeatingSchedule;
      await mount(tester, w);
      expect(find.text("19.5 °C"), findsOneWidget);
      expect(find.text("target 21 °C"), findsOneWidget);
      expect(find.text("Window 12 %"), findsOneWidget);
      expect(find.text("Manual 24 °C"), findsOneWidget);
      expect(find.text("Running"), findsOneWidget);
      expect(find.text("Today"), findsOneWidget);
      expect(find.text("Mon"), findsOneWidget);

      final open = w.height;
      await tester.tap(find.bySemanticsLabel("Hide week"));
      await tester.pump();
      expect(find.text("Mon"), findsNothing);
      expect(w.height, lessThan(open));
      expect(find.bySemanticsLabel("Show week"), findsOneWidget);
    });
  });
}
