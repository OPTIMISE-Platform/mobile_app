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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/tabs/sensors/sensor_picker.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

// Own file: a second picker test in one process does not get its requests
// answered (docs/testing.md).
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

  const devicesPath = "/device-repository/extended-devices";

  testWidgets("a failed page ends the list until the next search",
      (tester) async {
    final shown = <String>[];
    ErrorReporter.present = shown.add;
    await warmUpMgwStorage(tester);
    final backend = FakeBackend();
    backend.serveJson("GET", "/device-repository/device-groups", 200, []);
    backend.serveJson("GET", "/device-repository/extended-hubs", 200, []);
    backend.serveJson("GET", "/device-repository/device-types", 200, []);
    backend.serveJson("GET", "/device-repository/user-device-types", 200, []);
    backend.serveDevicesPaged([
      for (var i = 0; i < 60; i++)
        deviceJson("device-${i.toString().padLeft(2, '0')}", "Active $i"),
    ]);
    serveGoldenBackend(backend);

    late BuildContext capturedContext;
    await pumpGolden(
      tester,
      Builder(builder: (context) {
        capturedContext = context;
        return const SizedBox();
      }),
      dark: false,
    );
    unawaited(pickSensors(capturedContext));
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    List<(String?, String?)> pages() => backend.requests
        .where((r) => r.uri.path == devicesPath)
        .map((r) => (r.uri.queryParameters["search"], r.uri.queryParameters["offset"]))
        .toList();
    expect(pages(), [("", "0")]);

    Future<void> scrollToEnd() async {
      for (var i = 0; i < 12; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -400));
        await tester.pump();
      }
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    // A JSON body, so the failure is the status and not a parse error.
    final shownBefore = shown.length;
    backend.serveJson("GET", devicesPath, 500, {"error": "boom"});
    await scrollToEnd();
    expect(pages(), [("", "0"), ("", "50")], reason: "one failed attempt");
    expect(shown.skip(shownBefore), ["Could not load devices"],
        reason: "with rows on screen the toast is the only sign");

    // Scrolling away and back to the end does not ask again.
    await tester.drag(find.byType(ListView), const Offset(0, 1500));
    await tester.pump();
    await scrollToEnd();
    expect(pages(), [("", "0"), ("", "50")], reason: "no retry");
    expect(find.text("Active 49"), findsOneWidget,
        reason: "the rows stay, only paging ends");
    expect(find.byType(DelayedCircularProgressIndicator), findsNothing,
        reason: "no spinner for a page that is not coming");

    // The next search pages again, past its first page too.
    backend.stopServing("GET", devicesPath);
    await tester.enterText(find.byType(TextFormField), "Active");
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await scrollToEnd();
    expect(pages(), [("", "0"), ("", "50"), ("Active", "0"), ("Active", "50")]);
    expect(find.text("Active 59"), findsOneWidget);

    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  });
}
