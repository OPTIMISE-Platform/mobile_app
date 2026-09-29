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
import 'package:mobile_app/models/device_class.dart';
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
  });

  // One testWidgets for all cases: see docs/testing.md on a second test in
  // the same file whose screen makes requests.
  testWidgets(
      "the filter menu replaces the shared filter, applying each toggle at "
      "once and searching on OK", (tester) async {
    await tester.runAsync(() => Settings.setFilterMode(true));
    final backend = FakeBackend();
    backend.serveJson("GET", "/device-repository/device-groups", 200, []);
    backend.serveJson("GET", "/device-repository/extended-hubs", 200, []);
    backend.serveJson("GET", "/device-repository/device-types", 200, []);
    backend.serveJson("GET", "/device-repository/user-device-types", 200, []);
    backend.serveDevicesPaged([
      deviceJson("device-1", "Lamp"),
      deviceJson("device-2", "Heater"),
    ]);
    serveGoldenBackend(backend);
    await warmUpMgwStorage(tester);
    await pumpGolden(tester, const DeviceTabs(),
        dark: false, size: goldenSurfaceSize);
    final state = tester.state<DeviceTabsState>(find.byType(DeviceTabs));

    await tester.tap(find.text("Devices"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // A menu toggle hands over a new filter and leaves the old one as it was.
    final beforeToggle = state.filter;
    await tester.tap(find.byIcon(Icons.filter_alt));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Show inactive"));
    await tester.pumpAndSettle();
    expect(state.filter.showInactive, isTrue);
    expect(beforeToggle.showInactive, isFalse);

    // A dialog switch applies to the shared filter at once, but only OK
    // searches.
    AppState().deviceClasses["class-1"] = DeviceClass("class-1", "Lamps", "")
      ..deviceIds = ["device-1"];
    final beforeDialog = state.filter;
    final pagesBeforeDialog = _pageRequests(backend).length;
    await tester.tap(find.byIcon(Icons.filter_alt));
    await tester.pumpAndSettle();
    // The segment bar has a "Classes" tab of its own.
    await tester.tap(find.descendant(
        of: find.byType(PopupMenuItem<VoidCallback>),
        matching: find.text("Classes")));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(state.filter.deviceClassIds, ["class-1"]);
    expect(state.filter.showInactive, isTrue);
    expect(beforeDialog.deviceClassIds, isNull);
    expect(_pageRequests(backend).length, pagesBeforeDialog);

    await tester.tap(find.text("OK"));
    await tester.pumpAndSettle();
    expect(_pageRequests(backend).length, pagesBeforeDialog + 1);
    expect(_pageRequests(backend).last.queryParameters["ids"], contains("device-1"));

    // Reset clears everything the Devices tab does not own.
    await tester.tap(find.byIcon(Icons.filter_alt));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Reset"));
    await tester.pumpAndSettle();
    expect(state.filter, DeviceSearchFilter.empty());

    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  });
}

/// Device page requests (limit 50), not the by-id status refreshes.
List<Uri> _pageRequests(FakeBackend backend) => backend.requests
    .map((r) => r.uri)
    .where((u) =>
        u.path == "/device-repository/extended-devices" &&
        u.queryParameters["limit"] == "50")
    .toList();
