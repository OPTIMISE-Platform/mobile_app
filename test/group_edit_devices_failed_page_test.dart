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
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/tabs/groups/group_edit_devices.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

// Own file: a second group-editing test in one process does not get its
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

  testWidgets("a failed candidates page is not asked again every frame",
      (tester) async {
    final shown = <String>[];
    ErrorReporter.present = shown.add;
    final backend = FakeBackend();
    // A full page, so the list asks for a second one.
    backend.serveJson("POST", helper, 200, {
      "options": [
        for (var i = 0; i < 50; i++)
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

    int helperRequests() =>
        backend.requests.where((r) => r.uri.path == helper).length;
    expect(find.text("Candidate 0"), findsOneWidget);
    expect(helperRequests(), 1);

    final shownBefore = shown.length;
    backend.serveJson("POST", helper, 500, {"error": "boom"});
    // To the end of the list, where the next page is asked for.
    for (var i = 0; i < 15; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();
    }
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(helperRequests(), 2, reason: "one failed attempt");

    // Rebuilding the end of the list, by scrolling it away and back, does not
    // ask again either.
    await tester.drag(find.byType(ListView), const Offset(0, 1500));
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -3000));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(helperRequests(), 2, reason: "no retry loop");
    expect(shown.skip(shownBefore), ["Could not load group candidates"]);
    expect(find.text("Candidate 49"), findsOneWidget,
        reason: "the last candidate shows, not a spinner in its place");
    expect(find.byType(DelayedCircularProgressIndicator), findsNothing,
        reason: "nothing is loading any more");
  });
}
