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
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/widgets/tabs/groups/group_edit_devices.dart';

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

  // Both themes come out of one test: DioFactory (and the services built on
  // it) memoize their setup Future for the whole process, and awaiting that
  // Future from a *different* testWidgets zone than the one that created it
  // never resolves - see the comment in golden_device_tabs_shell_test.dart.
  testWidgets("group edit devices", (tester) async {
    for (final dark in [false, true]) {
      final suffix = dark ? "dark" : "light";

      final backend = FakeBackend();
      backend.serveJson("POST", "/device-selection/device-group-helper", 200, {
        "options": [
          {"device": deviceJson("device-1", "Living room lamp"), "removes_criteria": []},
          {"device": deviceJson("device-2", "Heat pump"), "removes_criteria": []},
        ],
        "criteria": [],
      });
      serveGoldenBackend(backend);

      final group = DeviceGroup("group-1", "Ground floor", null, "", [], null);
      await pumpGolden(tester, GroupEditDevices(group), dark: dark);
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile("goldens/group_edit_devices_$suffix.png"));

      resetAppStateForGolden();
      resetGoldenBackend();
    }
  });
}
