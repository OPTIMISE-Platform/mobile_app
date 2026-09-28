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

// Own file: a second picker test in one process does not get its requests
// answered (docs/testing.md).
void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  testWidgets(
      "a query typed while the first page is in flight replaces that page",
      (tester) async {
    await warmUpMgwStorage(tester);
    final backend = FakeBackend();
    backend.serveJson("GET", "/device-repository/device-groups", 200, []);
    backend.serveJson("GET", "/device-repository/extended-hubs", 200, []);
    backend.serveJson("GET", "/device-repository/device-types", 200, []);
    backend.serveJson("GET", "/device-repository/user-device-types", 200, []);
    backend.serveDevicesPaged([
      deviceJson("lamp-1", "Lamp One"),
      deviceJson("plug-1", "Plug One"),
    ]);
    backend.holdDevices = Completer<void>();
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
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    List<String?> searches() => backend.requests
        .where((r) => r.uri.path == "/device-repository/extended-devices")
        .map((r) => r.uri.queryParameters["search"])
        .toList();
    expect(searches(), [""]);

    // Past the picker's 300ms debounce, while page one is still held.
    await tester.enterText(find.byType(TextFormField), "plug");
    await tester.pump(const Duration(milliseconds: 400));
    expect(searches(), ["", "plug"],
        reason: "the new query's request goes out despite the one in flight");

    backend.holdDevices!.complete();
    backend.holdDevices = null;
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text("Plug One"), findsOneWidget);
    expect(find.text("Lamp One"), findsNothing,
        reason: "the old query's page must not land in the new list");
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  });
}
