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
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/widgets/tabs/processes/processes_list.dart';

import 'golden_helper.dart';
import 'process_backend.dart';

// Own file: a screen that makes requests runs in one testWidgets per file
// (docs/testing.md).
void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
    resetGoldenBackend();
    ErrorReporter.resetForTest();
    ErrorReporter.present = (_) {};
  });

  testWidgets(
      "a failed load shows an inline error that is reported once, and Retry "
      "loads the list; an empty list says so", (tester) async {
    final reported = <String>[];
    ErrorReporter.present = reported.add;
    final backend = ProcessBackend(
      deployments: [deploymentJson("d1", "Heating")],
      instances: [instanceJson("i1", "d1", "Heating", state: "completed")],
    );
    backend.deploymentsStatus = 500;
    serveGoldenBackend(backend);

    await pumpGolden(
        tester, const Scaffold(body: ProcessesList()), dark: false);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text("Could not load processes"), findsOneWidget);
    expect(find.text("Retry"), findsOneWidget);
    expect(find.text("Heating"), findsNothing);
    expect(reported, ["Could not load processes"]);

    backend.deploymentsStatus = null;
    await tester.tap(find.text("Retry"));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text("Could not load processes"), findsNothing);
    expect(find.text("Heating"), findsOneWidget);
    expect(find.text("Completed"), findsOneWidget);

    // Pull to refresh on an account that has no deployments left.
    backend.deployments.clear();
    backend.instances.clear();
    await tester.fling(find.text("Heating"), const Offset(0, 400), 1000);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text("No Processes"), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });
}
