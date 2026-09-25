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
import 'package:mobile_app/widgets/tabs/sensors/sensor_sparkline.dart';
import 'package:mobile_app/widgets/tabs/sensors/sensor_values.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

final _fixedNow = DateTime.utc(2026, 1, 1, 12);

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

  // Both themes in one test - see golden_device_tabs_shell_test.dart for why.
  testWidgets("sensor values", (tester) async {
    for (final dark in [false, true]) {
      final suffix = dark ? "dark" : "light";

      final backend = FakeBackend();
      backend.serveJson("GET", "/device-repository/extended-devices", 200,
          [deviceJson("device-1", "Living room lamp", deviceTypeId: "device-type-1")]);
      backend.serveJson("POST", "/device-command/commands/batch", 200,
          [{"status_code": 200, "message": 22.5}]);
      // A fixed "now", so the points sit at the same x on every run.
      sparklineClock = () => _fixedNow;
      // 5m buckets over the 2h window, as the real query returns them.
      backend.serveJson("POST", "/db/v3/queries", 200, [
        [
          for (var i = 23; i >= 0; i--)
            [
              _fixedNow.subtract(Duration(minutes: 5 * i)).toIso8601String(),
              21.0 + (i % 6 - 3).abs() * 0.3 + (23 - i) * 0.05,
            ],
        ],
      ]);
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
