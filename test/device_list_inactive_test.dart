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
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/widgets/tabs/device_tabs.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() async {
    resetAppStateForGolden();
    resetGoldenBackend();
    await Settings.setFilterMode(false);
    await Settings.setFavoriteDeviceIds({});
  });

  /// A backend that answers the metadata calls AppState.init() makes with
  /// empty lists, so only /extended-devices (registered by the caller) is
  /// interesting - the same shortcut device_tabs_navigation_test.dart uses.
  FakeBackend backendWithoutMetadata() {
    final backend = FakeBackend();
    backend.serveJson("GET", "/device-repository/device-groups", 200, []);
    backend.serveJson("GET", "/device-repository/extended-hubs", 200, []);
    backend.serveJson("GET", "/device-repository/device-types", 200, []);
    backend.serveJson("GET", "/device-repository/user-device-types", 200, []);
    return backend;
  }

  group("pagination with inactive devices hidden", () {
    test(
        "a page that is entirely inactive is followed by one with active "
        "devices, which appear once it loads", () async {
      final backend = backendWithoutMetadata();
      backend.serveDevicesPaged([
        for (var i = 0; i < 50; i++)
          deviceJson("inactive-$i", "Inactive $i", inactive: true),
        deviceJson("active-1", "Active 1"),
        deviceJson("active-2", "Active 2"),
      ]);
      serveGoldenBackend(backend);

      await AppState().searchDevices(DeviceSearchFilter.empty(), true);
      // The whole first (raw, 50-device) page was inactive: nothing visible
      // yet, but the raw fetch cursor moved and the list isn't done.
      expect(AppState().devices, isEmpty);
      expect(AppState().allDevicesLoaded, isFalse);
      expect(AppState().rawDevicesFetched, 50);

      // What the list's own scroll-triggered pagination would do next.
      await AppState().loadDevices();

      expect(AppState().devices.map((d) => d.id).toList(),
          ["active-1", "active-2"]);
      expect(AppState().allDevicesLoaded, isTrue);
      expect(AppState().rawDevicesFetched, 52);
      await _settleBackgroundWork();
    });

    test(
        "a mixed page's raw size, not its filtered size, decides whether "
        "more pages follow", () async {
      final backend = backendWithoutMetadata();
      // Exactly one full (50-device) raw page, so more might follow even
      // though most of it is hidden and only 30 end up visible.
      backend.serveDevicesPaged([
        for (var i = 0; i < 20; i++)
          deviceJson("inactive-$i", "Inactive $i", inactive: true),
        for (var i = 0; i < 30; i++) deviceJson("active-$i", "Active $i"),
      ]);
      serveGoldenBackend(backend);

      await AppState().searchDevices(DeviceSearchFilter.empty(), true);

      expect(AppState().devices, hasLength(30));
      // Wrong if this read the filtered page size (30 < 50): the list would
      // stop here instead of asking for a (possibly empty) next page.
      expect(AppState().allDevicesLoaded, isFalse);
      expect(AppState().rawDevicesFetched, 50);

      await AppState().loadDevices();

      expect(AppState().devices, hasLength(30));
      expect(AppState().allDevicesLoaded, isTrue);
      expect(AppState().rawDevicesFetched, 50);
      await _settleBackgroundWork();
    });
  });

  group("the \"Show inactive\" filter toggle", () {
    testWidgets("off hides an inactive device, on reveals it again",
        (tester) async {
      await tester.runAsync(() => Settings.setFilterMode(true));
      final backend = backendWithoutMetadata();
      backend.serveDevicesPaged([
        deviceJson("active-1", "Active device"),
        deviceJson("inactive-1", "Inactive device", inactive: true),
      ]);
      serveGoldenBackend(backend);
      await warmUpMgwStorage(tester);
      await pumpGolden(tester, const DeviceTabs(),
          dark: false, size: goldenSurfaceSize);

      await tester.tap(find.text("Devices"));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text("Active device"), findsOneWidget);
      expect(find.text("Inactive device"), findsNothing);

      await tester.tap(find.byIcon(Icons.filter_alt));
      await tester.pumpAndSettle();
      await tester.tap(find.text("Show inactive"));
      await tester.pumpAndSettle();

      expect(find.text("Active device"), findsOneWidget);
      expect(find.text("Inactive device"), findsOneWidget);

      // Toggling back off hides it again.
      await tester.tap(find.byIcon(Icons.filter_alt));
      await tester.pumpAndSettle();
      await tester.tap(find.text("✓ Show inactive"));
      await tester.pumpAndSettle();

      expect(find.text("Inactive device"), findsNothing);
      await _settleWidgetBackgroundWork(tester);
    });
  });

  group("DeviceList widget", () {
    testWidgets(
        "does not get stuck on \"No Devices\" when the first page is "
        "entirely inactive", (tester) async {
      final backend = backendWithoutMetadata();
      backend.serveDevicesPaged([
        for (var i = 0; i < 50; i++)
          deviceJson("inactive-$i", "Inactive $i", inactive: true),
        deviceJson("active-1", "Active 1"),
      ]);
      serveGoldenBackend(backend);
      await warmUpMgwStorage(tester);
      await pumpGolden(tester, const DeviceTabs(),
          dark: false, size: goldenSurfaceSize);

      await tester.tap(find.text("Devices"));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The empty-but-not-done state used to read as "No Devices" and never
      // build the row that fetches the next (visible) page.
      expect(find.text("No Devices"), findsNothing);
      expect(find.text("Active 1"), findsOneWidget);
      await _settleWidgetBackgroundWork(tester);
    });
  });

  group("Favorites", () {
    test("a favorites-scoped search does not hide an inactive favourite",
        () async {
      // Favorites are stored per account (Settings._getFavoriteIds) - without
      // one, getFavoriteDeviceIds() always answers empty.
      await Settings.setAccount("test-account");
      await Settings.setFavoriteDeviceIds({"inactive-1"});
      final backend = backendWithoutMetadata();
      backend.serveDevicesPaged([
        deviceJson("inactive-1", "Inactive favourite", inactive: true),
      ]);
      serveGoldenBackend(backend);

      // What DeviceTabsState._applyTabConfig does for the Favorites tab.
      final filter = DeviceSearchFilter.empty()..favorites = true;
      await AppState().searchDevices(filter, true);

      expect(AppState().devices.map((d) => d.id).toList(), ["inactive-1"]);
      await _settleBackgroundWork();
    });
  });
}

/// loadDevices() kicks off a background states/connection-status refresh it
/// does not await (see DeviceMixin._loadStatesInBackground); left running,
/// it can still be mid-request when tearDown swaps the fake backend back out
/// from under it and throws well after this test has already finished.
Future<void> _settleBackgroundWork() =>
    Future<void>.delayed(const Duration(milliseconds: 100));

/// Same, for a testWidgets body: several short pumps instead of one, so a
/// background chain of more than one sequential await (states, then device
/// types, then connection status) gets more than one microtask turn to
/// finish - not just draining loadDevices()'s own background work, but
/// keeping it from leaking into (and stalling on a still-locked mutex in)
/// whichever test runs next.
Future<void> _settleWidgetBackgroundWork(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
