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

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/tabs/groups/group_edit_devices.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

// Own file: a second testWidgets in the same process may never get its
// requests answered (docs/testing.md).
void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    ErrorReporter.resetForTest();
    ErrorReporter.present = (_) {};
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  const helper = "/device-selection/device-group-helper";

  testWidgets("a failed reload after a selection ends the spinner and toasts",
      (tester) async {
    final shown = <String>[];
    ErrorReporter.present = shown.add;
    final backend = FakeBackend();
    backend.serveJson("POST", helper, 200, {
      "options": [
        for (var i = 0; i < 5; i++)
          {
            "device": deviceJson("device-$i", "Candidate $i"),
            "removes_criteria": [],
          },
      ],
      "criteria": [],
    });
    serveGoldenBackend(backend);
    final group = DeviceGroup("group-1", "Ground floor", null, "", [], null);
    await pumpGolden(tester, GroupEditDevices(group), dark: false);
    expect(find.text("Candidate 0"), findsOneWidget);

    // Picking a candidate reloads the candidates for the new selection.
    final shownBefore = shown.length;
    backend.serveJson("POST", helper, 500, {"error": "boom"});
    await tester.tap(find.text("Candidate 2"));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(shown.skip(shownBefore), ["Could not load group candidates"]);
    expect(find.byType(DelayedCircularProgressIndicator), findsNothing,
        reason: "the spinner must not outlive the failed request");
    expect(find.text("Candidate 2"), findsOneWidget,
        reason: "the selection stays");
    expect(find.text("Candidate 0"), findsNothing,
        reason: "no candidates for a reload that failed");
  });
}
