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

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/services/devices.dart';
import 'package:mobile_app/services/settings.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

DeviceInstance _device(String id, {bool inactive = false}) =>
    DeviceInstance.fromJson(deviceJson(id, id, inactive: inactive));

FakeBackend _backendWithoutMetadata() {
  final backend = FakeBackend();
  backend.serveJson("GET", "/device-repository/device-groups", 200, []);
  backend.serveJson("GET", "/device-repository/extended-hubs", 200, []);
  backend.serveJson("GET", "/device-repository/device-types", 200, []);
  backend.serveJson("GET", "/device-repository/user-device-types", 200, []);
  return backend;
}

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() async {
    AppState().readCachedInactiveDeviceIds =
        DevicesService.getCachedInactiveDeviceIds;
    resetAppStateForGolden();
    resetGoldenBackend();
    await Settings.setFavoriteDeviceIds({});
  });

  test(
      "hides inactive devices, keeps inactive favourites and devices never "
      "seen", () async {
    await Settings.setAccount("test-account");
    await Settings.setFavoriteDeviceIds({"inactive-fav"});
    AppState().noteDevices([
      _device("active"),
      _device("inactive", inactive: true),
      _device("inactive-fav", inactive: true),
    ]);

    expect(
        AppState().visibleDeviceCount(
            ["active", "inactive", "inactive-fav", "never-seen"]),
        3);
  });

  test("a device seen active again counts again", () {
    AppState().noteDevices([_device("d", inactive: true)]);
    expect(AppState().visibleDeviceCount(["d"]), 0);
    AppState().noteDevices([_device("d")]);
    expect(AppState().visibleDeviceCount(["d"]), 1);
  });

  test("a full replace drops devices no longer in the account", () {
    AppState().noteDevices([_device("gone", inactive: true)]);
    AppState().replaceDeviceIndex([_device("other")]);
    expect(AppState().visibleDeviceCount(["gone"]), 1);
  });

  test("a fetched page feeds the count, and \"Show inactive\" counts all",
      () async {
    final backend = _backendWithoutMetadata();
    backend.serveDevicesPaged([
      deviceJson("a", "A"),
      deviceJson("b", "B", inactive: true),
    ]);
    serveGoldenBackend(backend);

    await AppState().searchDevices(DeviceSearchFilter.empty(), true);
    expect(AppState().visibleDeviceCount(["a", "b"]), 1);

    await AppState()
        .searchDevices(DeviceSearchFilter.empty()..showInactive = true);
    expect(AppState().visibleDeviceCount(["a", "b"]), 2);
    await _settle();
  });

  group("seeding from the device cache", () {
    test("adds the cached inactive devices without a request", () async {
      final backend = FakeBackend();
      serveGoldenBackend(backend);
      AppState().readCachedInactiveDeviceIds = () async => {"cached"};

      await AppState().loadInactiveDeviceIds();

      expect(AppState().visibleDeviceCount(["cached", "other"]), 1);
      expect(backend.requests, isEmpty);
    });

    test("does not override a device noted while the cache was read",
        () async {
      final read = Completer<Set<String>>();
      AppState().readCachedInactiveDeviceIds = () => read.future;

      final seed = AppState().loadInactiveDeviceIds();
      // Fetched as active after the seed started reading the older row.
      AppState().noteDevices([_device("d")]);
      read.complete({"d"});
      await seed;

      expect(AppState().visibleDeviceCount(["d"]), 1);
    });

    test("is discarded when the device data is cleared meanwhile", () async {
      final read = Completer<Set<String>>();
      AppState().readCachedInactiveDeviceIds = () => read.future;

      final seed = AppState().loadInactiveDeviceIds();
      // A logout while the previous account's cache is being read.
      AppState().clearDeviceData();
      read.complete({"d"});
      await seed;

      expect(AppState().visibleDeviceCount(["d"]), 1);
    });
  });
}

/// Lets the states refresh that loadDevices() starts without awaiting finish.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 50));
