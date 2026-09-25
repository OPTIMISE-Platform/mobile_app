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
import 'package:mobile_app/widgets/shared/multi_select_field.dart';
import 'package:mobile_app/widgets/tabs/sensors/name_icon_dialog.dart';

import 'golden_helper.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
  });

  // Opens the dialog built by [open] on a plain screen and lets its route
  // transition finish; pump(duration) rather than pumpAndSettle, consistent
  // with the other golden tests in this suite even though nothing here
  // animates forever.
  Future<void> openDialog(WidgetTester tester, bool dark,
      void Function(BuildContext) open) async {
    await pumpGolden(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => open(context),
            child: const Text("Open"),
          ),
        ),
      ),
      dark: dark,
    );
    await tester.tap(find.text("Open"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  for (final dark in [false, true]) {
    final suffix = dark ? "dark" : "light";

    testWidgets("name/icon dialog ($suffix)", (tester) async {
      await openDialog(
        tester,
        dark,
        (context) => showNameIconDialog(
          context,
          title: "Edit sensor",
          initialName: "Living room lamp",
        ),
      );
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile("goldens/name_icon_dialog_$suffix.png"));
    });

    testWidgets("multi select dialog ($suffix)", (tester) async {
      await openDialog(
        tester,
        dark,
        (context) => showMultiSelectDialog(
          context,
          title: "Chargers",
          options: const [
            MultiSelectOption("Living room lamp", group: "Devices"),
            MultiSelectOption("Heat pump", group: "Devices"),
            MultiSelectOption("Ground floor", group: "Groups"),
          ],
          selected: const [1],
        ),
      );
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile("goldens/multi_select_dialog_$suffix.png"));
    });

    testWidgets("update dialog ($suffix)", (tester) async {
      AppUpdater.currentBuild = 120;
      AppUpdater.latestBuild = 123;
      AppUpdater.downloadSize = 18500000;
      AppUpdater.updateDate = DateTime.utc(2026, 3, 4, 9, 30);
      await openDialog(
        tester,
        dark,
        (context) => AppUpdater.showUpdateDialog(context),
      );
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile("goldens/update_dialog_$suffix.png"));
    });
  }
}
