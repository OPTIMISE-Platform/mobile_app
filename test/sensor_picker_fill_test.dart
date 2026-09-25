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
import 'package:mobile_app/widgets/tabs/sensors/sensor_picker.dart';

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

  FakeBackend backendWith(List<Map<String, dynamic>> devices) {
    final backend = FakeBackend();
    backend.serveJson("GET", "/device-repository/device-groups", 200, []);
    backend.serveJson("GET", "/device-repository/extended-hubs", 200, []);
    backend.serveJson("GET", "/device-repository/device-types", 200, []);
    backend.serveJson("GET", "/device-repository/user-device-types", 200, []);
    backend.serveDevicesPaged(devices);
    return backend;
  }

  List<String?> pageOffsets(FakeBackend backend) => backend.requests
      .where((r) => r.uri.path == "/device-repository/extended-devices")
      .map((r) => r.uri.queryParameters["offset"])
      .toList();

  // A full raw page with only five rows to show, then a short second page.
  List<Map<String, dynamic>> sparseFirstPage() => [
        for (var i = 0; i < 45; i++)
          deviceJson("inactive-$i", "A Inactive $i", inactive: true),
        for (var i = 0; i < 5; i++) deviceJson("active-$i", "B Active $i"),
        for (var i = 0; i < 10; i++) deviceJson("later-$i", "C Later $i"),
      ];

  Future<void> openPicker(WidgetTester tester, {int frames = 20}) async {
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
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  // One testWidgets for all cases: only the first widget test of a process
  // got its picker requests answered, the memoized-setup pattern
  // docs/testing.md describes.
  testWidgets("the picker pages on its own until its rows fill the viewport",
      (tester) async {
    await warmUpMgwStorage(tester);

    // Five rows cannot scroll, so the scroll listener alone never asks for
    // page two.
    var backend = backendWith(sparseFirstPage());
    serveGoldenBackend(backend);
    await openPicker(tester);
    expect(find.text("C Later 0"), findsOneWidget,
        reason: "next page after a sparse one");
    expect(pageOffsets(backend), ["0", "50"]);

    // A page that fills the viewport does not pull the next one.
    resetAppStateForGolden();
    backend = backendWith([
      for (var i = 0; i < 120; i++)
        deviceJson("active-${i.toString().padLeft(3, '0')}", "Active $i"),
    ]);
    serveGoldenBackend(backend);
    await openPicker(tester);
    expect(find.text("Active 0"), findsOneWidget);
    expect(pageOffsets(backend), ["0"], reason: "no fetch beyond the viewport");

    // A failed next page is not retried on its own. Page one is held past
    // the route check, so only what follows it meets the failing route.
    resetAppStateForGolden();
    backend = backendWith(sparseFirstPage());
    backend.holdDevices = Completer<void>();
    serveGoldenBackend(backend);
    await openPicker(tester, frames: 5);
    expect(pageOffsets(backend), ["0"]);
    backend.serveJson(
        "GET", "/device-repository/extended-devices", 500, "boom");
    backend.holdDevices!.complete();
    backend.holdDevices = null;
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text("B Active 0"), findsOneWidget);
    expect(pageOffsets(backend), ["0", "50"],
        reason: "one failed attempt, no retry loop");

    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  });
}
