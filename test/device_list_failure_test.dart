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
import 'package:mobile_app/widgets/tabs/device_tabs.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

// Own file: run after the other widget tests of device_list_inactive_test.dart
// the network list never loaded - the memoized-setup pattern docs/testing.md
// describes for tests sharing a process.
void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  FakeBackend backendWithoutMetadata() {
    final backend = FakeBackend();
    backend.serveJson("GET", "/device-repository/device-groups", 200, []);
    backend.serveJson("GET", "/device-repository/extended-hubs", 200, []);
    backend.serveJson("GET", "/device-repository/device-types", 200, []);
    backend.serveJson("GET", "/device-repository/user-device-types", 200, []);
    return backend;
  }

  group("a failed page load", () {
    testWidgets(
        "in a network's device list ends in \"No Devices\" instead of "
        "requesting on every frame, and pull-to-refresh retries",
        (tester) async {
      final backend = backendWithoutMetadata();
      backend.serveJson("GET", "/device-repository/extended-hubs", 200, [
        {
          "id": "net-1",
          "name": "Net One",
          "hash": "",
          "owner_id": "owner-1",
          "shared": false,
          "device_local_ids": ["d-0-local"],
          "device_ids": ["d-0"],
          "connection_state": "online",
        }
      ]);
      backend.serveDevicesPaged([
        for (var i = 0; i < 60; i++) deviceJson("d-$i", "Dev $i"),
      ]);
      serveGoldenBackend(backend);
      await warmUpMgwStorage(tester);
      await pumpGolden(tester, const DeviceTabs(),
          dark: false, size: goldenSurfaceSize);

      // Leaves 60 of 60 as totalDevices, so a failed page would otherwise
      // keep a placeholder row in the network's list.
      await tester.tap(find.text("Devices"));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text("Networks"));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      backend.serveJson(
          "GET", "/device-repository/extended-devices", 500, "boom");
      final before = _pageRequests(backend);
      await tester.tap(find.text("Net One"));
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(_pageRequests(backend) - before, 1);
      expect(find.text("No Devices"), findsOneWidget);

      backend.stopServing("GET", "/device-repository/extended-devices");
      await tester.fling(
          find.text("No Devices"), const Offset(0, 400), 1000);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(_pageRequests(backend) - before, 2);
      expect(find.text("No Devices"), findsNothing);
      expect(find.text("Dev 0"), findsOneWidget);
      await _settleWidgetBackgroundWork(tester);
    });

    testWidgets("on the first page leaves the Devices tab at \"No Devices\"",
        (tester) async {
      final backend = backendWithoutMetadata();
      backend.serveJson(
          "GET", "/device-repository/extended-devices", 500, "boom");
      serveGoldenBackend(backend);
      await warmUpMgwStorage(tester);
      await pumpGolden(tester, const DeviceTabs(),
          dark: false, size: goldenSurfaceSize);

      await tester.tap(find.text("Devices"));
      await tester.pump();
      final before = _pageRequests(backend);
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(find.text("No Devices"), findsOneWidget);
      expect(_pageRequests(backend) - before, lessThanOrEqualTo(1));
      await _settleWidgetBackgroundWork(tester);
    });
  });
}

/// Device page requests, not the by-id status refreshes that follow a page.
int _pageRequests(FakeBackend backend) => backend.requests
    .where((r) =>
        r.uri.path == "/device-repository/extended-devices" &&
        !r.uri.queryParameters.containsKey("ids"))
    .length;

/// Lets the states/connection refresh that loadDevices() starts without
/// awaiting finish before tearDown swaps the backend out.
Future<void> _settleWidgetBackgroundWork(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
