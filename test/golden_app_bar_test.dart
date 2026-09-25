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
import 'package:mobile_app/services/app_update.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/widgets/shared/app_bar.dart';

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

  Widget appBarScreen() => Builder(
        builder: (context) => Scaffold(
          appBar: const MyAppBar("Devices").getAppBar(context, []),
          body: const SizedBox.shrink(),
        ),
      );

  Widget appBarDefaultActionsScreen() => Builder(
        builder: (context) => Scaffold(
          appBar: const MyAppBar("Devices")
              .getAppBar(context, MyAppBar.getDefaultActions(context)),
          body: const SizedBox.shrink(),
        ),
      );

  for (final dark in [false, true]) {
    final suffix = dark ? "dark" : "light";

    testWidgets("app bar ($suffix)", (tester) async {
      // Hive's write Future never resolves inside testWidgets' fake-async
      // zone without runAsync - reads are fine (Hive serves them from its
      // in-memory cache), only the write's completion hangs.
      await tester.runAsync(() => Settings.setLocalMode(false));
      await pumpGolden(tester, appBarScreen(), dark: dark);
      await expectLater(
          find.byType(MaterialApp), matchesGoldenFile("goldens/app_bar_$suffix.png"));
    });

    testWidgets("app bar, local mode ($suffix)", (tester) async {
      await tester.runAsync(() => Settings.setLocalMode(true));
      await pumpGolden(tester, appBarScreen(), dark: dark);
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile("goldens/app_bar_local_mode_$suffix.png"));
    });

    // The update check stops at updateSupported (Android only) before its
    // own Dio, which the backend seam would not reach.
    testWidgets("app bar, default actions ($suffix)", (tester) async {
      expect(AppUpdater.updateSupported, isFalse);
      final backend = FakeBackend();
      backend.serveJson("GET", "/notifications-v2/notifications", 200,
          {"notifications": [], "offset": 0, "limit": 0});
      serveGoldenBackend(backend);
      await tester.runAsync(() => Settings.setLocalMode(false));
      await pumpGolden(tester, appBarDefaultActionsScreen(), dark: dark);
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile("goldens/app_bar_default_actions_$suffix.png"));
    });
  }
}
