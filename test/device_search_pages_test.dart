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
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/widgets/shared/paged_device_list.dart';

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

  FakeBackend backendWithoutMetadata() {
    final backend = FakeBackend();
    backend.serveJson("GET", "/device-repository/device-groups", 200, []);
    backend.serveJson("GET", "/device-repository/extended-hubs", 200, []);
    backend.serveJson("GET", "/device-repository/device-types", 200, []);
    backend.serveJson("GET", "/device-repository/user-device-types", 200, []);
    return backend;
  }

  // loadDevices() leaves a states refresh running; see
  // device_list_inactive_test.dart.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 100));

  group("DeviceSearchPages", () {
    test("ends after a failed page: no next-page row, and a new token",
        () async {
      final backend = backendWithoutMetadata();
      backend.serveJson(
          "GET", "/device-repository/extended-devices", 500, "boom");
      serveGoldenBackend(backend);
      final pages = DeviceSearchPages(AppState());
      final before = pages.pageToken;

      await AppState().searchDevices(DeviceSearchFilter.empty(), true);

      expect(pages.ended, isTrue);
      expect(pages.hasMore, isFalse);
      expect(pages.pageToken, isNot(before));
    });

    test(
        "keeps asking after a page of only hidden devices, with a new token "
        "per page", () async {
      final backend = backendWithoutMetadata();
      backend.serveDevicesPaged([
        for (var i = 0; i < 50; i++)
          deviceJson("inactive-$i", "Inactive $i", inactive: true),
        deviceJson("active-1", "Active 1"),
      ]);
      serveGoldenBackend(backend);
      final pages = DeviceSearchPages(AppState());

      await AppState().searchDevices(DeviceSearchFilter.empty(), true);
      expect(AppState().devices, isEmpty);
      expect(pages.hasMore, isTrue);
      expect(pages.ended, isFalse);
      final afterFirst = pages.pageToken;

      pages.loadNextPage();
      await settle();
      expect(pages.pageToken, isNot(afterFirst));
      expect(AppState().devices.map((d) => d.id), ["active-1"]);
      expect(pages.hasMore, isFalse);
      expect(pages.ended, isTrue);
    });

    test(
        "untilEnded asks past the server's total, which a full last page "
        "reaches before the search has ended", () async {
      final backend = backendWithoutMetadata();
      backend.serveDevicesPaged([
        for (var i = 0; i < 50; i++) deviceJson("active-$i", "Active $i"),
      ]);
      serveGoldenBackend(backend);

      await AppState().searchDevices(DeviceSearchFilter.empty(), true);
      expect(AppState().devices, hasLength(50));
      expect(AppState().totalDevices, 50);
      expect(AppState().devicesListEnded, isFalse);

      expect(DeviceSearchPages(AppState()).hasMore, isFalse);
      expect(DeviceSearchPages(AppState(), untilEnded: true).hasMore, isTrue);
      await settle();
    });

    test("gets a new token when the device data is cleared", () async {
      final pages = DeviceSearchPages(AppState());
      final before = pages.pageToken;
      AppState().clearDeviceData();
      expect(pages.pageToken, isNot(before));
    });
  });
}
