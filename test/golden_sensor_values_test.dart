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

@Tags(['golden'])
library;

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
  });

  // Both themes in one test - see golden_device_tabs_shell_test.dart for why.
  testWidgets("sensor values", (tester) async {
    for (final dark in [false, true]) {
      final suffix = dark ? "dark" : "light";

      final backend = FakeBackend();
      backend.serveJson("GET", "/device-repository/extended-devices", 200,
          [deviceJson("device-1", "Living room lamp", deviceTypeId: "device-type-1")]);
      backend.serveJson("POST", "/device-command/commands/batch", 200,
          [{"status_code": 200, "message": 22.5}]);
      // /db/v3/queries (the sparkline history) is deliberately left
      // unserved (404): loadSparklineValues catches every error and just
      // skips the sparkline, and its x axis is real DateTime.now() at fetch
      // time - any fixture "now" recorded here is a few real milliseconds
      // older by then, which shifts the fill's antialiased edge by a
      // sub-pixel amount that flips its rounding from run to run. A 404
      // here is exactly what an offline history query looks like anyway.
      serveGoldenBackend(backend);
      await warmUpMgwStorage(tester);

      // AppState.deviceTypes already has the type, so ensureDeviceTypes (used
      // while loading the pinned device) has nothing to fetch.
      AppState().deviceTypes["device-type-1"] = _deviceType();
      AppState().platformFunctions["function-1"] =
          PlatformFunction("function-1", "temperature", "concept-1", "Temperature");

      const tab = SensorTab(
        id: "tab-1",
        name: "Living room",
        pins: [
          SensorPin(
            deviceId: "device-1",
            functionId: "function-1",
            aspectId: "aspect-1",
            serviceGroupKey: "group-1",
          ),
        ],
      );
      await tester.runAsync(() => Settings.setSensorTabs([tab]));

      await pumpGolden(
          tester, const Scaffold(body: SensorValues()), dark: dark);
      // Lets the sparkline (fetched after the value) arrive on screen too.
      await tester.pump(const Duration(milliseconds: 300));
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile("goldens/sensor_values_$suffix.png"));

      resetAppStateForGolden();
      resetGoldenBackend();
    }
  });
}
