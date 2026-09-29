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
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/widgets/tabs/device_tabs.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/detail_page.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() async {
    resetAppStateForGolden();
    resetGoldenBackend();
    await Settings.setFavoriteDeviceIds({});
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets(
      "returning from a group opened on Favorites searches with the "
      "favourites scope again", (tester) async {
    await tester.runAsync(() async {
      // Favourites are per account; without one the list reads as empty.
      await Settings.setAccount("test-account");
      await Settings.setFavoriteDeviceIds({"fav-1"});
    });
    final backend = FakeBackend();
    backend.serveJson("GET", "/device-repository/device-groups", 200, []);
    backend.serveJson("GET", "/device-repository/extended-hubs", 200, []);
    backend.serveJson("GET", "/device-repository/device-types", 200, []);
    backend.serveJson("GET", "/device-repository/user-device-types", 200, []);
    backend.serveDevicesPaged([
      deviceJson("fav-1", "Lamp"),
      deviceJson("other-1", "Heater"),
    ]);
    serveGoldenBackend(backend);
    await warmUpMgwStorage(tester);
    await pumpGolden(tester, const DeviceTabs(),
        dark: false, size: goldenSurfaceSize);
    await settle(tester);
    final state = tester.state<DeviceTabsState>(find.byType(DeviceTabs));

    // The start page is Favorites, and it keeps its scope in the filter.
    expect(state.filter.favorites, isTrue);
    expect(_pageRequests(backend).last.queryParameters["ids"], "fav-1");

    // A favourite group whose member is not a favourite device, so its own
    // search is told apart from the favourites one.
    AppState().deviceGroups.add(
        DeviceGroup("group-1", "Ground floor", null, "", ["other-1"], null)
          ..favorite = true);
    AppState().notifyListeners();
    await tester.pump();

    // textContaining: the favourite star is a WidgetSpan in the same text.
    await tester.tap(find.textContaining("Ground floor"));
    await settle(tester);
    expect(find.byType(DetailPage), findsOneWidget);
    expect(_pageRequests(backend).last.queryParameters["ids"],
        contains("other-1"));

    Navigator.of(tester.element(find.byType(DetailPage))).pop();
    await settle(tester);

    expect(state.filter.favorites, isTrue);
    expect(_pageRequests(backend).last.queryParameters["ids"], "fav-1");
  });
}

/// Device page requests (limit 50), not the by-id status refreshes.
List<Uri> _pageRequests(FakeBackend backend) => backend.requests
    .map((r) => r.uri)
    .where((u) =>
        u.path == "/device-repository/extended-devices" &&
        u.queryParameters["limit"] == "50")
    .toList();
