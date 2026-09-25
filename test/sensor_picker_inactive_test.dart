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

  testWidgets(
      "a mixed page's raw offset, not its filtered count, drives the "
      "next page request", (tester) async {
    final backend = FakeBackend();
    backend.serveJson("GET", "/device-repository/device-groups", 200, []);
    backend.serveJson("GET", "/device-repository/extended-hubs", 200, []);
    backend.serveJson("GET", "/device-repository/device-types", 200, []);
    backend.serveJson("GET", "/device-repository/user-device-types", 200, []);
    // One full (50-device) raw page: 20 hidden, 30 visible.
    backend.serveDevicesPaged([
      for (var i = 0; i < 20; i++)
        deviceJson("inactive-$i", "Inactive $i", inactive: true),
      for (var i = 0; i < 30; i++) deviceJson("active-$i", "Active $i"),
    ]);
    serveGoldenBackend(backend);
    // pickSensors reaches AppState.init() (via ensureInitialized()), which
    // reads paired gateways through MgwStorage - its first Hive box open
    // never resolves inside this test's fake-async zone otherwise.
    await warmUpMgwStorage(tester);

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
    // Not pumpAndSettle: the picker's DelayedCircularProgressIndicator shows
    // a real CircularProgressIndicator once loading takes a moment, whose
    // implicit animation never settles on its own.
    await tester.pump(); // starts the route push
    for (var i = 0;
        i < 20 && find.byType(ListView).evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Scrolls past the picker's own "load more" threshold. Several smaller
    // drags, not one huge one: each step's position update is what the
    // scroll listener needs to see, not just the drag's end point.
    for (var i = 0; i < 15; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 300));

    final offsets = backend.requests
        .where((r) => r.uri.path == "/device-repository/extended-devices")
        .map((r) => r.uri.queryParameters["offset"])
        .toList();
    // Wrong (30, the visible count so far) would re-fetch and duplicate the
    // last ten devices already shown, instead of the ones beyond 50.
    expect(offsets, ["0", "50"]);
  });
}
