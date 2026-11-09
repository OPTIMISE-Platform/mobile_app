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
import 'package:mobile_app/services/smart_service.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/base.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/heating_schedule.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/shared/widget_info.dart';
import 'package:mobile_app/widgets/tabs/smart-services/heating_schedule_model.dart';
import 'package:mobile_app/widgets/tabs/smart-services/instance_parameters.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

const _repo = "/smart-services/repository";

// The platform returns a multiple device selection as one JSON text holding a
// list of JSON texts, one per option value.
String _selection(String deviceId, String label) =>
    json.encode([json.encode({"device_selection": {"device_id": deviceId, "service_id": null, "path": null}, "label": label})]);

final _thermostats = _selection("urn:infai:ses:device:c14a6d2e-243a-4c7a-a879-68e1dca1e187", "CT Thermostat");

Map<String, dynamic> _instance({String schedule = '{"windows":[]}', String? thermostats}) => {
      "description": "",
      "design_id": "design-1",
      "id": "inst-1",
      "name": "Heating",
      "release_id": "rel-1",
      "user_id": "user-1",
      "error": null,
      "ready": true,
      "deleting": false,
      "new_release_id": null,
      "parameters": [
        {"id": "thermostats", "label": "Thermostats", "value": thermostats ?? _thermostats, "value_label": "CT Thermostat"},
        {"id": "schedule", "label": "Schedule", "value": schedule, "value_label": null},
        {"id": "setback", "label": "Setback", "value": 17, "value_label": null},
      ],
    };

Map<String, dynamic> _param(String id, String type, {bool multiple = false, List<Map<String, dynamic>>? options}) => {
      "id": id,
      "label": id,
      "description": "",
      "default_value": null,
      "multiple": multiple,
      "optional": false,
      "options": options,
      "type": type,
      "characteristic_id": null,
      "characteristic": null,
      "value": null,
      "value_label": null,
    };

// Plain tests, not testWidgets: each one makes requests (docs/testing.md).
void main() {
  bodyLayout();

  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  late FakeBackend backend;
  setUp(() {
    backend = FakeBackend();
    backend.serveJson("GET", "$_repo/instances/inst-1", 200, _instance());
    backend.serveJson("GET", "$_repo/releases/rel-1/parameters", 200, [
      _param("thermostats", "https://schema.org/Text", multiple: true, options: [
        {"kind": "device", "label": "CT Thermostat", "value": json.decode(_thermostats)[0], "needs_same_entity_id_in_parameter": null, "entity_id": null},
      ]),
      _param("schedule", "https://schema.org/Text"),
      _param("setback", "https://schema.org/Integer"),
    ]);
    backend.serveJson("PUT", "$_repo/instances/inst-1/parameters", 200, _instance());
    serveGoldenBackend(backend);
  });

  tearDown(() {
    resetGoldenBackend();
  });

  Map<String, dynamic> sentParameters() {
    final put = backend.requests.singleWhere((r) => r.method == "PUT");
    expect(put.uri.path, "$_repo/instances/inst-1/parameters");
    expect(put.uri.queryParameters.containsKey("release_id"), isFalse);
    return {for (final p in json.decode(put.data as String) as List) p["id"]: p};
  }

  test("saving sends every parameter, the thermostats with the content they have", () async {
    final instance = await SmartServiceService.getInstance("inst-1");
    final plan = HeatingSchedule.parse('{"windows":[{"weekdays":[0],"from":"07:00","to":"08:30","temperature":21.5}]}', 18);

    await saveHeatingSchedule(instance, plan);

    final sent = sentParameters();
    expect(sent.keys, ["thermostats", "schedule", "setback"]);
    // as the generic edit flow sends it: the list itself, not its JSON text
    expect(sent["thermostats"]["value"], json.decode(_thermostats));
    expect(sent["schedule"]["value"], plan.serialise());
    expect(sent["setback"]["value"], 18);
  });

  test("saving uses the thermostats the instance has now, not those of the last refresh", () async {
    final stale = await SmartServiceService.getInstance("inst-1");
    final newer = _selection("urn:infai:ses:device:other", "Other");
    backend.serveJson("GET", "$_repo/instances/inst-1", 200, _instance(thermostats: newer));

    await saveHeatingSchedule(stale, const HeatingSchedule(HeatingSchedule.defaultWindows, 17));

    expect(sentParameters()["thermostats"]["value"], json.decode(newer));
  });

  Future<SmSeHeatingSchedule> refreshed() async {
    final w = (await SmartServiceModuleWidget.fromWidgetInfo(
        "heating_schedule", WidgetInfo.fromJson({"widget_type": smSeHeatingScheduleType, "widget_data": {}}))) as SmSeHeatingSchedule;
    w.instance_id = "inst-1";
    await w.refresh();
    return w;
  }

  test("the widget shows the plan, and a plan it cannot read as a message", () async {
    expect((await refreshed()).height, 13);

    backend.serveJson("GET", "$_repo/instances/inst-1", 200, _instance(schedule: "kein json"));
    expect((await refreshed()).height, 3);

    backend.serveJson("GET", "$_repo/instances/inst-1", 403, {"message": "no"});
    expect((await refreshed()).height, 3);
  });
}

// The widget body at phone width and at a larger text size must lay out
// without overflow.
void bodyLayout() {
  for (final scale in [1.0, 1.6]) {
    testWidgets("the body lays out at text scale $scale", (tester) async {
      final backend = FakeBackend();
      backend.serveJson("GET", "$_repo/instances/inst-1", 200,
          _instance(schedule: '{"windows":[{"weekdays":[0,1,2,3,4],"from":"22:00","to":"06:00","temperature":19.5}]}'));
      serveGoldenBackend(backend);
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final w = SmSeHeatingSchedule()
        ..id = "heating_schedule"
        ..instance_id = "inst-1"
        ..widgetInfo = WidgetInfo.fromJson({"widget_type": smSeHeatingScheduleType, "widget_data": {}});
      await tester.runAsync(w.refresh);
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
        home: Scaffold(body: Builder(builder: (context) => w.build(context, false))),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text("Edit plan"), findsOneWidget);
      expect(find.text("Mon"), findsOneWidget);
    });
  }
}
