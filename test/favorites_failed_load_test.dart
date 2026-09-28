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
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/tabs/device_tabs.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

// Own file: the shell's requests are only answered for the first widget test
// of a process that makes them (docs/testing.md).
void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() async {
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  testWidgets(
      "a failed first device load ends the Favorites spinner, and "
      "pull-to-refresh retries", (tester) async {
    // Without a stored favourite the favourites search answers locally and
    // never reaches the failing route.
    await tester.runAsync(() async {
      await Settings.setAccount("test-account");
      await Settings.setFavoriteDeviceIds({"fav-1"});
    });
    addTearDown(() => tester.runAsync(() => Settings.setFavoriteDeviceIds({})));

    final backend = FakeBackend();
    backend.serveJson("GET", "/device-repository/device-groups", 200, []);
    backend.serveJson("GET", "/device-repository/extended-hubs", 200, []);
    backend.serveJson("GET", "/device-repository/device-types", 200, []);
    backend.serveJson("GET", "/device-repository/user-device-types", 200, []);
    backend.serveJson(
        "GET", "/device-repository/extended-devices", 500, "boom");
    serveGoldenBackend(backend);
    await warmUpMgwStorage(tester);
    await pumpGolden(tester, const DeviceTabs(),
        dark: false, size: goldenSurfaceSize);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(
        backend.requests
            .where((r) => r.uri.path == "/device-repository/extended-devices"),
        isNotEmpty,
        reason: "the favourites load must have reached the failing route");
    expect(find.byType(DelayedCircularProgressIndicator), findsNothing);
    expect(find.text("Add Favorites"), findsOneWidget);

    backend.stopServing("GET", "/device-repository/extended-devices");
    backend.serveDevicesPaged([deviceJson("fav-1", "Favourite lamp")]);
    await tester.fling(find.text("Add Favorites"), const Offset(0, 400), 1000);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // The favourite star is a WidgetSpan, so the title is not an exact match.
    expect(find.textContaining("Favourite lamp", findRichText: true),
        findsOneWidget);
    expect(find.text("Add Favorites"), findsNothing);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  });
}
