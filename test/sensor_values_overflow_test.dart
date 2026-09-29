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
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/models/function.dart';
import 'package:mobile_app/models/sensor_pin.dart';
import 'package:mobile_app/models/sensor_tab.dart';
import 'package:mobile_app/models/service.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/widgets/tabs/sensors/sensor_sparkline.dart';
import 'package:mobile_app/widgets/tabs/sensors/sensor_values.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

// Matches state_helper_test.dart's fixture: one service, one output, one
// state - functionId/aspectId/serviceGroupKey/path below all come from it.
DeviceType _deviceType() {
  final contentVariable = ContentVariable("cv-1", "value", null, null,
      "aspect-1", "function-1", "https://schema.org/Float", null, null, null);
  final output = Content("content-1", "json", "segment-1", contentVariable);
  final service = Service("service-1", "local-service-1", "Service 1", "",
      "protocol-1", "event", "group-1", null, [output]);
  return DeviceType("device-type-1", "Type 1", "", "class-1", [service], null);
}

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
    resetGoldenBackend();
    sparklineClock = DateTime.now;
  });

  Future<void> pumpGrid(WidgetTester tester,
      {required double width, required double scale}) async {
    final backend = FakeBackend();
    // A name long enough to need two lines even at 412dp, and a function
    // display name that wraps to two lines at every width/scale tested -
    // the two labels a card's fixed height used to have no room for.
    backend.serveJson(
        "GET",
        "/device-repository/extended-devices",
        200,
        [
          deviceJson(
              "device-1", "Basement dehumidifier north-west storage room unit two",
              deviceTypeId: "device-type-1")
        ]);
    backend.serveJson("POST", "/device-command/commands/batch", 200, [
      {"status_code": 200, "message": 22.5}
    ]);
    // No history - the sparkline is not what this test is about.
    backend.serveJson("POST", "/db/v3/queries", 200, [[]]);
    serveGoldenBackend(backend);
    await warmUpMgwStorage(tester);

    AppState().deviceTypes["device-type-1"] = _deviceType();
    AppState().platformFunctions["function-1"] = PlatformFunction(
        "function-1",
        "temperature",
        "concept-1",
        "Outdoor relative air humidity sensor");

    const tab = SensorTab(id: "tab-1", name: "Living room", pins: [
      SensorPin(
        deviceId: "device-1",
        functionId: "function-1",
        aspectId: "aspect-1",
        // A pin in the current format; one without the list is rewritten on
        // load, from inside the fake-async zone where the Hive write never ends.
        aspectIds: ["aspect-1"],
        serviceGroupKey: "group-1",
      ),
    ]);
    await tester.runAsync(() => Settings.setSensorTabs([tab]));

    await pumpGolden(
      tester,
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: const Scaffold(body: SensorValues()),
        ),
      ),
      dark: false,
      size: Size(width, 800),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  // One testWidgets for every combination, not one each: Dio instances are
  // memoized for the process (see docs/testing.md), so a getDevices future
  // created against one test's FakeBackend can outlive it and never resolve
  // against the next test's.
  testWidgets("sensor value card fits at every phone width and text scale",
      (tester) async {
    for (final width in [320.0, 360.0, 412.0]) {
      for (final scale in [1.0, 1.3, 1.5, 2.0]) {
        final errors = <FlutterErrorDetails>[];
        final oldOnError = FlutterError.onError;
        FlutterError.onError = (d) => errors.add(d);

        await pumpGrid(tester, width: width, scale: scale);

        FlutterError.onError = oldOnError;
        expect(errors, isEmpty,
            reason: "at ${width}dp, scale $scale:\n"
                "${errors.map((e) => e.exceptionAsString()).join('\n')}");

        // The value survives, even if its own FittedBox had to shrink it.
        expect(find.textContaining("22.5"), findsOneWidget,
            reason: "at ${width}dp, scale $scale");

        resetAppStateForGolden();
        resetGoldenBackend();
      }
    }
  });
}
