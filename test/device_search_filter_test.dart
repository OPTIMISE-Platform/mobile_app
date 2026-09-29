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

/// One id-list field with its per-id copy methods.
class _IdField {
  final String name;
  final List<String>? Function(DeviceSearchFilter) read;
  final DeviceSearchFilter Function(DeviceSearchFilter, String) withId;
  final DeviceSearchFilter Function(DeviceSearchFilter, String) withoutId;

  const _IdField(this.name, this.read, this.withId, this.withoutId);
}

final _idFields = [
  _IdField("deviceClassIds", (f) => f.deviceClassIds,
      (f, id) => f.withDeviceClass(id), (f, id) => f.withoutDeviceClass(id)),
  _IdField("deviceGroupIds", (f) => f.deviceGroupIds,
      (f, id) => f.withDeviceGroup(id), (f, id) => f.withoutDeviceGroup(id)),
  _IdField("locationIds", (f) => f.locationIds,
      (f, id) => f.withLocation(id), (f, id) => f.withoutLocation(id)),
  _IdField("networkIds", (f) => f.networkIds,
      (f, id) => f.withNetwork(id), (f, id) => f.withoutNetwork(id)),
];

/// Every field set to a value different from [DeviceSearchFilter.empty].
DeviceSearchFilter _full() => DeviceSearchFilter("lamp",
    deviceClassIds: ["class-1"],
    deviceIds: ["device-1"],
    deviceGroupIds: ["group-1"],
    locationIds: ["location-1"],
    networkIds: ["network-1"],
    favorites: true,
    showInactive: true);

void main() {
  group("construction", () {
    test("copies the id lists it is given", () {
      final ids = ["class-1"];
      final filter = DeviceSearchFilter("", deviceClassIds: ids);

      ids.add("class-2");

      expect(filter.deviceClassIds, ["class-1"]);
    });

    test("exposes unmodifiable id lists", () {
      final filter = _full();
      for (final list in [
        filter.deviceClassIds,
        filter.deviceIds,
        filter.deviceGroupIds,
        filter.locationIds,
        filter.networkIds,
      ]) {
        expect(() => list!.add("x"), throwsUnsupportedError);
      }
    });
  });

  group("copyWith()", () {
    test("without arguments equals the original", () {
      expect(_full().copyWith(), equals(_full()));
      expect(DeviceSearchFilter.empty().copyWith(),
          equals(DeviceSearchFilter.empty()));
    });

    test("replaces only the fields it is given", () {
      final copy = _full().copyWith(
          query: "heater", locationIds: ["location-2"], showInactive: false);

      expect(copy.query, "heater");
      expect(copy.locationIds, ["location-2"]);
      expect(copy.showInactive, isFalse);
      expect(copy.deviceClassIds, ["class-1"]);
      expect(copy.deviceIds, ["device-1"]);
      expect(copy.deviceGroupIds, ["group-1"]);
      expect(copy.networkIds, ["network-1"]);
      expect(copy.favorites, isTrue);
    });

    test("leaves the original unchanged", () {
      final original = _full();
      original.copyWith(query: "heater", deviceClassIds: ["class-2"]);
      expect(original, equals(_full()));
    });
  });

  group("without()", () {
    final clears = <String, DeviceSearchFilter Function(DeviceSearchFilter)>{
      "deviceClassIds": (f) => f.without(deviceClassIds: true),
      "deviceIds": (f) => f.without(deviceIds: true),
      "deviceGroupIds": (f) => f.without(deviceGroupIds: true),
      "locationIds": (f) => f.without(locationIds: true),
      "networkIds": (f) => f.without(networkIds: true),
      "favorites": (f) => f.without(favorites: true),
    };

    Object? read(DeviceSearchFilter f, String name) => switch (name) {
          "deviceClassIds" => f.deviceClassIds,
          "deviceIds" => f.deviceIds,
          "deviceGroupIds" => f.deviceGroupIds,
          "locationIds" => f.locationIds,
          "networkIds" => f.networkIds,
          "favorites" => f.favorites,
          _ => throw ArgumentError(name),
        };

    for (final entry in clears.entries) {
      test("clears ${entry.key} to null and keeps every other field", () {
        final cleared = entry.value(_full());

        expect(read(cleared, entry.key), isNull);
        for (final other in clears.keys.where((k) => k != entry.key)) {
          expect(read(cleared, other), read(_full(), other), reason: other);
        }
        expect(cleared.query, "lamp");
        expect(cleared.showInactive, isTrue);
      });
    }

    test("without flags equals the original", () {
      expect(_full().without(), equals(_full()));
    });
  });

  group("per-id copies", () {
    for (final field in _idFields) {
      test("adding to ${field.name} returns a new filter", () {
        final original = DeviceSearchFilter.empty();
        final one = field.withId(original, "a");
        final two = field.withId(one, "b");

        expect(field.read(original), isNull);
        expect(field.read(one), ["a"]);
        expect(field.read(two), ["a", "b"]);
      });

      test("adding an id already in ${field.name} does not repeat it", () {
        final one = field.withId(DeviceSearchFilter.empty(), "a");
        expect(field.read(field.withId(one, "a")), ["a"]);
      });

      test("removing from ${field.name} leaves the original alone", () {
        final two =
            field.withId(field.withId(DeviceSearchFilter.empty(), "a"), "b");
        final one = field.withoutId(two, "a");

        expect(field.read(two), ["a", "b"]);
        expect(field.read(one), ["b"]);
      });

      test("removing the last ${field.name} entry clears it to null", () {
        final one = field.withId(DeviceSearchFilter.empty(), "a");
        final none = field.withoutId(one, "a");

        expect(field.read(none), isNull);
        expect(none, equals(DeviceSearchFilter.empty()));
      });

      test("removing an id not in ${field.name} changes nothing", () {
        final one = field.withId(DeviceSearchFilter.empty(), "a");
        expect(field.read(field.withoutId(one, "b")), ["a"]);
        expect(field.read(field.withoutId(DeviceSearchFilter.empty(), "b")),
            isNull);
      });
    }
  });

  group("equality", () {
    test("holds for equal field values, with a matching hashCode", () {
      expect(_full(), equals(_full()));
      expect(_full().hashCode, _full().hashCode);
      expect(DeviceSearchFilter.empty(), equals(DeviceSearchFilter("")));
    });

    final variants = <String, DeviceSearchFilter>{
      "query": _full().copyWith(query: "heater"),
      "deviceClassIds": _full().copyWith(deviceClassIds: ["class-2"]),
      "deviceIds": _full().copyWith(deviceIds: ["device-2"]),
      "deviceGroupIds": _full().copyWith(deviceGroupIds: ["group-2"]),
      "locationIds": _full().copyWith(locationIds: ["location-2"]),
      "networkIds": _full().copyWith(networkIds: ["network-2"]),
      "favorites": _full().copyWith(favorites: false),
      "showInactive": _full().copyWith(showInactive: false),
    };
    for (final entry in variants.entries) {
      test("tells apart filters that differ only in ${entry.key}", () {
        expect(entry.value, isNot(equals(_full())));
      });
    }

    test("tells a null id list apart from an empty one", () {
      // Null places no constraint; an empty list matches no device.
      expect(DeviceSearchFilter("", deviceIds: []),
          isNot(equals(DeviceSearchFilter.empty())));
    });

    test("tells favorites null apart from false", () {
      expect(DeviceSearchFilter("", favorites: false),
          isNot(equals(DeviceSearchFilter.empty())));
    });

    test("ignores the order and repetition of ids", () {
      final a = DeviceSearchFilter("", locationIds: ["l-1", "l-2"]);
      final b = DeviceSearchFilter("", locationIds: ["l-2", "l-1", "l-2"]);

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test("tells apart filters whose lists print the same", () {
      // ["a, b"] and ["a", "b"] both print as [a, b].
      expect(DeviceSearchFilter("", deviceClassIds: ["a, b"]),
          isNot(equals(DeviceSearchFilter("", deviceClassIds: ["a", "b"]))));
    });
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

      // Each menu tap hands over a new filter with one class more.
      final filter = DeviceSearchFilter.empty().withDeviceClass("class-1");
      await AppState().searchDevices(filter, true);
      expect(_pageRequests(backend), 1);

      await AppState().searchDevices(filter.withDeviceClass("class-2"));

      expect(_pageRequests(backend), 2);
      // loadDevices() starts a states refresh it does not await; let it finish
      // before tearDown swaps the backend out.
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });

    test("does not search again for an equal filter with reordered ids",
        () async {
      final backend = FakeBackend();
      backend.serveJson("GET", "/device-repository/device-groups", 200, []);
      backend.serveJson("GET", "/device-repository/extended-hubs", 200, []);
      backend.serveJson("GET", "/device-repository/device-types", 200, []);
      backend.serveJson("GET", "/device-repository/user-device-types", 200, []);
      backend.serveDevicesPaged([deviceJson("device-1", "Device 1")]);
      serveGoldenBackend(backend);

      final filter = DeviceSearchFilter("", deviceClassIds: ["class-1", "class-2"]);
      await AppState().searchDevices(filter, true);
      expect(_pageRequests(backend), 1);

      // Removing and re-adding a class in the menu reorders the list.
      await AppState().searchDevices(
          filter.withoutDeviceClass("class-1").withDeviceClass("class-1"));

      expect(_pageRequests(backend), 1);
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
