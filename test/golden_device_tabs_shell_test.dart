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
import 'package:mobile_app/widgets/tabs/device_tabs.dart';

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

  // Empty lists everywhere: groups/networks/devices load and settle without
  // the per-group detail fetch DeviceGroupsService issues for a non-empty
  // list, and every metadata loader AppState.init() runs is left unmatched -
  // they catch their own errors, so a 404 there is equivalent to "no data".
  FakeBackend emptyBackend() {
    final backend = FakeBackend();
    backend.serveJson("GET", "/device-repository/device-groups", 200, []);
    backend.serveJson("GET", "/device-repository/extended-hubs", 200, []);
    backend.serveJson("GET", "/device-repository/extended-devices", 200, []);
    return backend;
  }

  for (final dark in [false, true]) {
    final suffix = dark ? "dark" : "light";

    // Both goldens for a theme are captured from the same test: DioFactory
    // and friends memoize their setup Futures at the top level for the whole
    // process, and awaiting one of those Futures from a *different*
    // testWidgets zone than the one that created it never resolves - the
    // shell and its drawer have to share a zone, so they share a test.
    testWidgets("device tabs shell ($suffix)", (tester) async {
      serveGoldenBackend(emptyBackend());
      await warmUpMgwStorage(tester);
      await pumpGolden(tester, const DeviceTabs(), dark: dark);
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile("goldens/device_tabs_shell_$suffix.png"));

      // Golden 2: drawer opened - it holds MyTheme.isDarkMode/textColor. The
      // untimed pump lets the tap's setState (which starts the drawer's own
      // AnimationController) land before the timed pump advances it - a timed
      // pump right after tap() leaves the slide-in animation at its start.
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile("goldens/device_tabs_shell_drawer_$suffix.png"));
    });
  }
}
