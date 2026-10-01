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
import 'package:mobile_app/models/device_class.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/services/device_types.dart';
import 'package:mobile_app/services/devices.dart';
import 'package:mobile_app/services/settings.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

DeviceInstance _device(String id,
        {bool inactive = false, String type = "device-type-1"}) =>
    DeviceInstance.fromJson(
        deviceJson(id, id, inactive: inactive, deviceTypeId: type));

CachedDeviceIndex _index(
        {Map<String, String> types = const {},
        Set<String> inactive = const {},
        bool complete = true}) =>
    (deviceTypes: types, inactive: inactive, complete: complete);

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
    AppState().readCachedDeviceIndex = DevicesService.getCachedDeviceIndex;
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

    // The class rows follow the same rule once the index is complete.
    AppState().deviceTypes["device-type-1"] = _type("device-type-1", "lamp");
    AppState().replaceDeviceIndex([_device("a"), _device("b", inactive: true)]);
    expect(AppState().visibleDeviceCountOfClass("lamp"), 1);

    await AppState()
        .searchDevices(DeviceSearchFilter('', showInactive: true));
    expect(AppState().visibleDeviceCount(["a", "b"]), 2);
    expect(AppState().visibleDeviceCountOfClass("lamp"), 2);
    await _settle();
  });

  group("class counts", () {
    setUp(() {
      AppState().deviceTypes.addAll({
        "lamp-a": _type("lamp-a", "lamp"),
        "lamp-b": _type("lamp-b", "lamp"),
        "heater": _type("heater", "heating"),
      });
      // A replace reloads the types for a device of an unknown one.
      AppState().fetchDeviceTypes = (maxAge, {serveStale}) async =>
          AppState().deviceTypes.values.toList();
    });

    tearDown(() {
      AppState().fetchDeviceTypes = (maxAge, {serveStale}) =>
          DeviceTypesService.getDeviceTypes(null, maxAge, serveStale);
    });

    test("count the devices of the class's types, hiding inactive ones but "
        "not inactive favourites", () async {
      await Settings.setAccount("test-account");
      await Settings.setFavoriteDeviceIds({"inactive-fav"});
      AppState().replaceDeviceIndex([
        _device("a", type: "lamp-a"),
        _device("b", type: "lamp-b"),
        _device("inactive", type: "lamp-a", inactive: true),
        _device("inactive-fav", type: "lamp-a", inactive: true),
        _device("h", type: "heater"),
        _device("other", type: "unknown"),
      ]);

      expect(AppState().visibleDeviceCountOfClass("lamp"), 3);
      expect(AppState().visibleDeviceCountOfClass("heating"), 1);
    });

    test("a class none of whose devices is indexed shows no count, one whose "
        "devices are all hidden shows 0", () {
      AppState().replaceDeviceIndex([
        _device("off", type: "heater", inactive: true),
      ]);

      // Listed classes have a device of the user: the index is behind.
      expect(AppState().visibleDeviceCountOfClass("lamp"), isNull);
      expect(AppState().visibleDeviceCountOfClass("heating"), 0);
    });

    test("a count follows a type load that moves a type to another class", () {
      AppState().replaceDeviceIndex([_device("a", type: "lamp-a")]);
      expect(AppState().visibleDeviceCountOfClass("lamp"), 1);

      AppState().fetchDeviceTypes = (maxAge, {serveStale}) async =>
          [_type("lamp-a", "heating")];
      return AppState().loadDeviceTypes().then((_) {
        expect(AppState().visibleDeviceCountOfClass("lamp"), isNull);
        expect(AppState().visibleDeviceCountOfClass("heating"), 1);
      });
    });

    test("show no count until the index holds every device", () {
      // A page seen before any full refresh is part of the account only.
      AppState().noteDevices([_device("a", type: "lamp-a")]);
      expect(AppState().visibleDeviceCountOfClass("lamp"), isNull);

      AppState().replaceDeviceIndex([_device("a", type: "lamp-a")]);
      expect(AppState().visibleDeviceCountOfClass("lamp"), 1);

      // An account change empties the index without claiming no devices.
      AppState().replaceDeviceIndex(const [], complete: false);
      AppState().noteDevices([_device("b", type: "lamp-a")]);
      expect(AppState().visibleDeviceCountOfClass("lamp"), isNull);

      AppState().replaceDeviceIndex([_device("a", type: "lamp-a")]);
      AppState().clearDeviceData();
      expect(AppState().visibleDeviceCountOfClass("lamp"), isNull);
    });

    test("a seed counts only from a cache a full refresh has filled",
        () async {
      AppState().readCachedDeviceIndex = () async =>
          _index(types: {"a": "lamp-a"}, complete: false);
      await AppState().loadDeviceIndex();
      expect(AppState().visibleDeviceCountOfClass("lamp"), isNull);

      AppState().readCachedDeviceIndex = () async =>
          _index(types: {"a": "lamp-a", "h": "heater"}, inactive: {"h"});
      await AppState().loadDeviceIndex();
      expect(AppState().visibleDeviceCountOfClass("lamp"), 1);
      expect(AppState().visibleDeviceCountOfClass("heating"), 0);
    });

    test("a seed keeps the type of a device noted while it read", () async {
      final read = Completer<CachedDeviceIndex>();
      AppState().readCachedDeviceIndex = () => read.future;

      final seed = AppState().loadDeviceIndex();
      AppState().noteDevices([_device("d", type: "heater")]);
      read.complete(_index(types: {"d": "lamp-a"}));
      await seed;

      expect(AppState().visibleDeviceCountOfClass("heating"), 1);
      expect(AppState().visibleDeviceCountOfClass("lamp"), isNull);
    });

    test("a device seen with another type moves and notifies once", () {
      AppState().replaceDeviceIndex([_device("d", type: "lamp-a")]);
      // Builds the class map the note has to drop.
      expect(AppState().visibleDeviceCountOfClass("lamp"), 1);
      var notified = 0;
      void listener() => notified++;
      AppState().addListener(listener);
      addTearDown(() => AppState().removeListener(listener));

      AppState().noteDevices([_device("d", type: "heater")]);
      expect(notified, 1);
      expect(AppState().visibleDeviceCountOfClass("lamp"), isNull);
      expect(AppState().visibleDeviceCountOfClass("heating"), 1);

      AppState().noteDevices([_device("d", type: "heater")]);
      expect(notified, 1, reason: "nothing changed");
    });

    test("the used classes are those with a loaded type, in map order", () {
      AppState().deviceClasses.addAll({
        "sensors": DeviceClass("sensors", "Sensors", ""),
        "lamp": DeviceClass("lamp", "Lamps", ""),
        "heating": DeviceClass("heating", "Heating", ""),
      });

      expect(AppState().usedDeviceClasses.map((c) => c.id), ["lamp", "heating"]);
      expect(AppState().deviceTypeIdsOfClasses(["lamp"]), ["lamp-a", "lamp-b"]);

      AppState().deviceTypes["s"] = _type("s", "sensors");
      AppState().deviceTypes.remove("heater");
      expect(AppState().usedDeviceClasses.map((c) => c.id), ["sensors", "lamp"]);
    });

    test("a replace with a type not loaded reloads the types", () async {
      await AppState().loadDeviceTypes();
      final calls = <Duration>[];
      AppState().fetchDeviceTypes = (maxAge, {serveStale}) async {
        calls.add(maxAge);
        return [
          ...AppState().deviceTypes.values,
          _type("new-type", "sensors"),
        ];
      };

      final all = [
        _device("a", type: "lamp-a"),
        _device("b", type: "lamp-b"),
        _device("h", type: "heater"),
      ];
      AppState().replaceDeviceIndex(all);
      await pumpEventQueue();
      expect(calls, isEmpty, reason: "every type is loaded");

      AppState().replaceDeviceIndex([...all, _device("n", type: "new-type")]);
      await pumpEventQueue();
      expect(calls, [Duration.zero]);
      expect(AppState().deviceTypeIdsOfClasses(["sensors"]), ["new-type"]);
      expect(AppState().visibleDeviceCountOfClass("sensors"), 1);
    });

    test("no type reload from a replace before the types are loaded",
        () async {
      AppState().deviceTypes.clear();
      var calls = 0;
      AppState().fetchDeviceTypes = (maxAge, {serveStale}) async {
        calls++;
        return [];
      };

      AppState().replaceDeviceIndex([_device("a", type: "lamp-a")]);
      await pumpEventQueue();
      expect(calls, 0);

      // Loaded, even if empty: now a replace with a type reloads them.
      await AppState().loadDeviceTypes();
      expect(calls, 1);
      AppState().replaceDeviceIndex([_device("a", type: "lamp-a")]);
      await pumpEventQueue();
      expect(calls, 2);
    });

    test("a type without any device in the complete index reloads the "
        "types, once per such type and not within the retry delay", () async {
      var backendTypes = [_type("lamp-a", "lamp"), _type("heater", "heating")];
      final calls = <Duration>[];
      var fail = false;
      AppState().fetchDeviceTypes = (maxAge, {serveStale}) async {
        calls.add(maxAge);
        if (fail) throw Exception("offline");
        return backendTypes;
      };
      await AppState().loadDeviceTypes(maxAge: Duration.zero);
      calls.clear();

      // The last heater was deleted elsewhere: the type list is behind.
      backendTypes = [_type("lamp-a", "lamp")];
      AppState().replaceDeviceIndex([_device("a", type: "lamp-a")]);
      await pumpEventQueue();
      expect(calls, [Duration.zero]);
      expect(AppState().deviceTypes.keys, ["lamp-a"]);

      // A backend that keeps returning a type without devices is asked once.
      backendTypes = [_type("lamp-a", "lamp"), _type("pump", "pumps")];
      AppState().noteDevices([_device("a2", type: "lamp-a")]);
      await pumpEventQueue();
      expect(calls, hasLength(1), reason: "no type without devices yet");
      AppState().forgetUnavailableDeviceTypes();
      await AppState().loadDeviceTypes();
      await pumpEventQueue();
      expect(calls, hasLength(3), reason: "served, then reloaded once");
      AppState().replaceDeviceIndex([_device("a", type: "lamp-a")]);
      await pumpEventQueue();
      expect(calls, hasLength(3), reason: "pump was reloaded for already");

      // A failing reload waits for the retry delay.
      AppState().forgetUnavailableDeviceTypes();
      fail = true;
      AppState().replaceDeviceIndex([_device("b", type: "lamp-a")]);
      await pumpEventQueue();
      AppState().replaceDeviceIndex([_device("c", type: "lamp-a")]);
      await pumpEventQueue();
      expect(calls, hasLength(4));
    });

    test("with the platform's type list, the complete index says which "
        "types are the user's", () async {
      AppState().deviceTypesAreAll = () => true;
      addTearDown(() => AppState().deviceTypesAreAll =
          () => DeviceTypesService.userListIsAllTypes);
      AppState().fetchDeviceTypes = (maxAge, {serveStale}) async => [
            _type("lamp-a", "lamp"),
            _type("lamp-b", "lamp"),
            _type("heater", "heating"),
            _type("pump", "pumps"),
          ];
      await AppState().loadDeviceTypes();
      AppState().deviceClasses.addAll({
        for (final id in ["heating", "lamp", "pumps"])
          id: DeviceClass(id, id, ""),
      });

      // Until the index is complete, the loaded types are all there is.
      expect(AppState().usedDeviceClasses.map((c) => c.id),
          ["heating", "lamp", "pumps"]);

      AppState().replaceDeviceIndex([_device("a", type: "lamp-a")]);
      expect(AppState().usedDeviceClasses.map((c) => c.id), ["lamp"]);
      expect(AppState().deviceTypeIdsOfClasses(["lamp", "heating"]), ["lamp-a"]);
      expect(AppState().visibleDeviceCountOfClass("lamp"), 1);
    });
  });

  group("seeding from the device cache", () {
    test("adds the cached inactive devices without a request", () async {
      final backend = FakeBackend();
      serveGoldenBackend(backend);
      AppState().readCachedDeviceIndex =
          () async => _index(inactive: {"cached"});

      await AppState().loadDeviceIndex();

      expect(AppState().visibleDeviceCount(["cached", "other"]), 1);
      expect(backend.requests, isEmpty);
    });

    test("does not override a device noted while the cache was read",
        () async {
      final read = Completer<CachedDeviceIndex>();
      AppState().readCachedDeviceIndex = () => read.future;

      final seed = AppState().loadDeviceIndex();
      // Fetched as active after the seed started reading the older row.
      AppState().noteDevices([_device("d")]);
      read.complete(_index(inactive: {"d"}));
      await seed;

      expect(AppState().visibleDeviceCount(["d"]), 1);
    });

    test("is discarded when the device data is cleared meanwhile", () async {
      final read = Completer<CachedDeviceIndex>();
      AppState().readCachedDeviceIndex = () => read.future;

      final seed = AppState().loadDeviceIndex();
      // A logout while the previous account's cache is being read.
      AppState().clearDeviceData();
      read.complete(_index(inactive: {"d"}));
      await seed;

      expect(AppState().visibleDeviceCount(["d"]), 1);
    });
  });
}

DeviceType _type(String id, String classId) =>
    DeviceType(id, id, "", classId, [], null);

/// Lets the states refresh that loadDevices() starts without awaiting finish.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 50));
