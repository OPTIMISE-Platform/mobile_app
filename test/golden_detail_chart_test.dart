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
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/chart.dart';

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

  // Both themes in one test - see golden_device_tabs_shell_test.dart for why.
  testWidgets("detail page chart", (tester) async {
    for (final dark in [false, true]) {
      final suffix = dark ? "dark" : "light";

      final backend = FakeBackend();
      // Fixed, arbitrary timestamps: unlike the sparkline, this chart's axis
      // is built from the data's own timestamps, not from DateTime.now(), so
      // a wall-clock-independent fixture is both simpler and safe to reuse
      // byte-for-byte between runs.
      backend.serveJson("POST", "/db/v3/queries", 200, [
        [
          ["2026-01-01T10:00:00.000Z", 19.5],
          ["2026-01-01T10:05:00.000Z", 20.0],
          ["2026-01-01T10:10:00.000Z", 20.5],
        ]
      ]);
      serveGoldenBackend(backend);

      final state = DeviceState(20.5, "service-1", "service-group-1",
          "function-1", "aspect-1", false, null, null, "device-1", "value", "group");

      await pumpGolden(tester, Chart(state), dark: dark);
      await tester.pump(const Duration(milliseconds: 400));
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile("goldens/detail_chart_$suffix.png"));

      resetAppStateForGolden();
      resetGoldenBackend();
    }
  });
}
