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

import 'fake_backend.dart';
import 'golden_helper.dart';

/// One id-list field of [DeviceSearchFilter] with the filter's own mutators.
/// `deviceIds` has none, so it is mutated in place like the others would be.
class _ListField {
  final String name;
  final String seedId;
  final List<String>? Function(DeviceSearchFilter) read;
  final void Function(DeviceSearchFilter, String) add;
  final void Function(DeviceSearchFilter, String) remove;

  const _ListField(this.name, this.seedId, this.read, this.add, this.remove);
}

final _fields = [
  _ListField("deviceClassIds", "class-1", (f) => f.deviceClassIds,
      (f, id) => f.addDeviceClass(id), (f, id) => f.removeDeviceClass(id)),
  _ListField("deviceGroupIds", "group-1", (f) => f.deviceGroupIds,
      (f, id) => f.addDeviceGroup(id), (f, id) => f.removeDeviceGroup(id)),
  _ListField("locationIds", "location-1", (f) => f.locationIds,
      (f, id) => f.addLocation(id), (f, id) => f.removeLocation(id)),
  _ListField("networkIds", "network-1", (f) => f.networkIds,
      (f, id) => f.addNetwork(id), (f, id) => f.removeNetwork(id)),
  _ListField("deviceIds", "device-1", (f) => f.deviceIds,
      (f, id) => (f.deviceIds ??= []).add(id), (f, id) => f.deviceIds!.remove(id)),
];

DeviceSearchFilter _filterWithOneIdEach() {
  final filter = DeviceSearchFilter.empty();
  for (final field in _fields) {
    field.add(filter, field.seedId);
  }
  return filter;
}

void main() {
  group("clone()", () {
    test("equals its original", () {
      final original = _filterWithOneIdEach()
        ..query = "lamp"
        ..favorites = true
        ..showInactive = true;
      expect(original.clone(), equals(original));
      expect(DeviceSearchFilter.empty().clone(), equals(DeviceSearchFilter.empty()));
    });

    for (final field in _fields) {
      test("adding to a clone's ${field.name} leaves the original alone", () {
        final original = _filterWithOneIdEach();
        final copy = original.clone();

        field.add(copy, "second");

        expect(field.read(original), [field.seedId]);
        expect(copy, isNot(equals(original)));
      });

      test("adding to the original's ${field.name} leaves the clone alone", () {
        final original = _filterWithOneIdEach();
        final copy = original.clone();

        field.add(original, "second");

        expect(field.read(copy), [field.seedId]);
        expect(copy, isNot(equals(original)));
      });

      test("removing a clone's last ${field.name} entry leaves the original "
          "alone", () {
        final original = _filterWithOneIdEach();
        final copy = original.clone();

        field.remove(copy, field.seedId);

        expect(field.read(original), [field.seedId]);
      });
    }
  });

  group("AppState.searchDevices", () {
    setUpAll(() async {
      await setUpGoldenEnvironment();
    });

    tearDown(() async {
      resetAppStateForGolden();
      resetGoldenBackend();
    });

    test("searches again after a second class is added to the same filter",
        () async {
      final backend = FakeBackend();
      backend.serveJson("GET", "/device-repository/device-groups", 200, []);
      backend.serveJson("GET", "/device-repository/extended-hubs", 200, []);
      backend.serveJson("GET", "/device-repository/device-types", 200, []);
      backend.serveJson("GET", "/device-repository/user-device-types", 200, []);
      backend.serveDevicesPaged([deviceJson("device-1", "Device 1")]);
      serveGoldenBackend(backend);

      // The filter menu keeps one filter object and mutates it per tap.
      final filter = DeviceSearchFilter.empty()..addDeviceClass("class-1");
      await AppState().searchDevices(filter, true);
      expect(_pageRequests(backend), 1);

      filter.addDeviceClass("class-2");
      await AppState().searchDevices(filter);

      expect(_pageRequests(backend), 2);
      // loadDevices() starts a states refresh it does not await; let it finish
      // before tearDown swaps the backend out.
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
  });
}

/// Device page requests (they carry the list's sort order), not the by-id
/// refreshes that follow a page.
int _pageRequests(FakeBackend backend) => backend.requests
    .where((r) =>
        r.uri.path == "/device-repository/extended-devices" &&
        r.uri.queryParameters.containsKey("sort"))
    .length;
