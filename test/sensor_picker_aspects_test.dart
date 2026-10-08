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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/aspect.dart';
import 'package:mobile_app/models/content.dart';
import 'package:mobile_app/models/content_variable.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/models/function.dart';
import 'package:mobile_app/models/sensor_pin.dart';
import 'package:mobile_app/models/service.dart';
import 'package:mobile_app/widgets/tabs/sensors/sensor_picker.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  ContentVariable temperature(String name, List<String> aspectIds) => ContentVariable("cv-$name", name, null, null,
      aspectIds.first, "temperature", "https://schema.org/Float", null, null, null, aspectIds);

  testWidgets("values sharing their first aspect are listed apart and an old pin is recognised", (tester) async {
    await warmUpMgwStorage(tester);
    final backend = FakeBackend();
    backend.serveJson("GET", "/device-repository/device-groups", 200, []);
    backend.serveJson("GET", "/device-repository/extended-hubs", 200, []);
    backend.serveJson("GET", "/device-repository/device-types", 200, []);
    backend.serveJson("GET", "/device-repository/user-device-types", 200, []);
    backend.serveDevicesPaged([deviceJson("device-1", "Weather station", deviceTypeId: "dt-weather")]);
    serveGoldenBackend(backend);

    // Written before aspect lists: names only the aspect that sets this value
    // apart, which one of the two states contains.
    final legacyPin = SensorPin.fromJson({
      "deviceId": "device-1",
      "functionId": "temperature",
      "aspectId": "inside",
      "serviceGroupKey": "group-1",
      "isControlling": false,
    });

    late BuildContext capturedContext;
    await pumpGolden(
      tester,
      Builder(builder: (context) {
        capturedContext = context;
        return const SizedBox();
      }),
      dark: false,
    );
    unawaited(pickSensors(capturedContext, existing: [legacyPin]));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // After the picker's own metadata load, which replaces what it cannot fetch.
    AppState().platformFunctions["temperature"] = PlatformFunction("temperature", "temperature", "", "Temperature");
    AppState().aspects["air"] =
        Aspect("air", "Air", [Aspect("inside", "Inside", null), Aspect("outside", "Outside", null)]);
    final service = Service("service-1", "local-service-1", "Service 1", "", "protocol-1", "request", "group-1", null, [
      Content("content-1", "json", "segment-1", ContentVariable("root", "root", null, null, null, null,
          "https://schema.org/StructuredValue", [temperature("inside", ["air", "inside"]), temperature("outside", ["air", "outside"])], null, null)),
    ]);
    AppState().deviceTypes["dt-weather"] = DeviceType("dt-weather", "Weather", "", "class-1", [service], null);

    await tester.tap(find.text("Weather station"));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text("Temperature"), findsNWidgets(2));
    expect(find.text("Air, Inside · Already added"), findsOneWidget);
    expect(find.text("Air, Outside"), findsOneWidget);
    final rowKeys = tester
        .widgetList(find.byWidgetPredicate((w) => w.key is ValueKey<(String, String)>))
        .map((w) => (w.key! as ValueKey<(String, String)>).value)
        .where((k) => k.$1 == "values")
        .map((k) => k.$2)
        .toList();
    expect(rowKeys, hasLength(2));
    expect(rowKeys, everyElement(isNot(contains("#"))),
        reason: "each value needs its own row key, not one repeated by position");

    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  });

  testWidgets("a group lists a value once on its most specific aspects", (tester) async {
    await warmUpMgwStorage(tester);
    final backend = FakeBackend();
    backend.serveJson("GET", "/device-repository/device-groups", 200, []);
    backend.serveJson("GET", "/device-repository/extended-hubs", 200, []);
    backend.serveJson("GET", "/device-repository/device-types", 200, []);
    backend.serveJson("GET", "/device-repository/user-device-types", 200, []);
    backend.serveDevicesPaged([]);
    serveGoldenBackend(backend);

    late BuildContext capturedContext;
    await pumpGolden(
      tester,
      Builder(builder: (context) {
        capturedContext = context;
        return const SizedBox();
      }),
      dark: false,
    );
    unawaited(pickSensors(capturedContext));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // After the picker's own metadata load, which replaces what it cannot fetch.
    AppState().platformFunctions["binary"] = PlatformFunction("binary", "binary", "", "Binary State");
    for (final id in ["device", "lighting"]) {
      AppState().aspects[id] = Aspect(id, id == "device" ? "Device" : "Lighting", null);
    }
    // device-repository adds the subsets of [device, lighting] as criteria of
    // their own.
    AppState().deviceGroups.add(DeviceGroup("lamps", "Living room lamps", [
      for (final aspects in [
        ["device", "lighting"],
        ["device"],
        ["lighting"],
      ])
        DeviceGroupCriteria.fromJson({
          "aspect_id": aspects.first,
          "aspect_ids": aspects,
          "device_class_id": "",
          "function_id": "binary",
          "interaction": "request",
        }),
    ], "", [], null));

    await tester.tap(find.text("Groups"));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.text("Living room lamps"));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text("Binary State"), findsOneWidget);

    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  });
}
