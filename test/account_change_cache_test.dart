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

@Tags(['isar'])
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/cached_metadata.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/models/exception_log_element.dart';
import 'package:mobile_app/models/location.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/models/notification.dart' as app;
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/services/device_classes.dart';
import 'package:mobile_app/services/device_groups.dart';
import 'package:mobile_app/services/devices.dart';
import 'package:mobile_app/services/locations.dart';
import 'package:mobile_app/services/networks.dart';
import 'package:mobile_app/services/notifications.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/account_epoch.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/shared/isar.dart';
import 'package:mobile_app/shared/metadata_cache.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';
import 'test_helper.dart';

const _devicesPath = "/device-repository/extended-devices";

List<Map<String, dynamic>> _devices(int n, {String prefix = "d"}) =>
    [for (var i = 0; i < n; i++) deviceJson("$prefix$i", "Device $i")];

Future<void> _store(List<Map<String, dynamic>> devices) =>
    isar!.writeTxn(() async {
      await isar!.deviceInstances.clear();
      await isar!.deviceInstances
          .putAll(devices.map(DeviceInstance.fromJson).toList());
    });

/// Marks every collection as refreshed now, except the devices.
Future<void> _devicesOverdue() async {
  await Settings.clearCacheUpdated();
  for (final cache in ["deviceGroups", "networks", "locations"]) {
    await Settings.setCacheUpdated(cache);
  }
}

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 300 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late FakeBackend backend;

  int requestsTo(String path) =>
      backend.requests.where((r) => r.uri.path == path).length;

  setUpAll(() async {
    await setUpGoldenEnvironment();
    await openTestIsar([
      DeviceInstanceSchema,
      DeviceGroupSchema,
      NetworkSchema,
      LocationSchema,
      CachedMetadataSchema,
      ExceptionLogElementSchema,
      app.NotificationSchema,
    ]);
    await Settings.setFavoritesMoved(true);
    await Settings.setDeviceGroupsCachedWithAspectLists(true);
    Auth().loggedIn = true;
  });

  tearDownAll(() => Auth().loggedIn = false);

  setUp(() {
    backend = FakeBackend();
    serveGoldenBackend(backend);
  });

  tearDown(() {
    CacheHelper.afterDeviceChunkForTest = null;
    CacheHelper.afterDevicePruneForTest = null;
    resetGoldenBackend();
  });

  group("device refresh", () {
    // Stored and fetched ids differ, so the count tells old rows from new.
    test("a logout between two chunks keeps every stored row and stays due",
        () async {
      await _store(_devices(1200, prefix: "old"));
      await _devicesOverdue();
      backend.serveDevicesPaged(_devices(1200));
      var chunks = 0;
      CacheHelper.afterDeviceChunkForTest = () {
        if (++chunks == 1) AccountEpoch.advance();
      };

      await CacheHelper.scheduleCacheUpdates();

      expect(chunks, 1, reason: "the account changed after the first chunk");
      final ids = (await isar!.deviceInstances.where().findAll())
          .map((d) => d.id)
          .toSet();
      expect(ids.where((id) => id.startsWith("old")), hasLength(1200));
      expect(ids.length, 1700, reason: "the old rows plus the first chunk");
      expect(Settings.getCacheUpdated("devices"), isNull,
          reason: "still due, so the next resume retries");
    });

    test("a refresh stores each device once, in its chunks", () async {
      await _store([]);
      await _devicesOverdue();
      backend.serveDevicesPaged(_devices(1200));
      var chunks = 0;
      CacheHelper.afterDeviceChunkForTest = () {
        if (++chunks == 1) AccountEpoch.advance();
      };

      await CacheHelper.scheduleCacheUpdates();

      expect(await isar!.deviceInstances.count(), 500,
          reason: "only the first chunk landed");
    });

    test("an account change after the last chunk prunes nothing", () async {
      await _store(_devices(3));
      await _devicesOverdue();
      backend.serveDevicesPaged([deviceJson("d0", "Device 0")]);
      CacheHelper.afterDeviceChunkForTest = AccountEpoch.advance;

      await CacheHelper.scheduleCacheUpdates();

      expect(await isar!.deviceInstances.count(), 3);
      expect(Settings.getCacheUpdated("devices"), isNull);
    });

    test("an account change after the prune leaves the collection due",
        () async {
      await _store(_devices(3));
      await _devicesOverdue();
      backend.serveDevicesPaged([deviceJson("d0", "Device 0")]);
      CacheHelper.afterDevicePruneForTest = AccountEpoch.advance;

      await CacheHelper.scheduleCacheUpdates();

      expect(Settings.getCacheUpdated("devices"), isNull);
    });

    test("a tab's page is stored", () async {
      await _store([]);
      backend.serveDevicesPaged([deviceJson("d0", "Device 0")]);

      await DevicesService.getDevices(
          50, 0, DeviceSearchFilter(""), null, forceBackend: true);

      final rows = await isar!.deviceInstances.where().findAll();
      expect(rows.map((d) => d.id), ["d0"]);
    });

    test("a star tapped while the refresh writes its chunks is kept",
        () async {
      await Settings.setAccount("test-account");
      await Settings.setFavoriteDeviceIds({});
      addTearDown(() => Settings.setFavoriteDeviceIds({}));
      await _store([]);
      await _devicesOverdue();
      backend.serveDevicesPaged(_devices(600));
      // After the first chunk, before the second, which holds d550.
      CacheHelper.afterDeviceChunkForTest =
          () => unawaited(Settings.setFavoriteDeviceIds({"d550"}));

      await CacheHelper.scheduleCacheUpdates();

      final row =
          await isar!.deviceInstances.where().idEqualTo("d550").findFirst();
      expect(row!.favorite, isTrue);
    });

    test("a device gone from the platform is pruned", () async {
      await _store(_devices(3));
      await _devicesOverdue();
      backend.serveDevicesPaged([deviceJson("d0", "Device 0")]);

      await CacheHelper.scheduleCacheUpdates();

      final rows = await isar!.deviceInstances.where().findAll();
      expect(rows.map((d) => d.id), ["d0"]);
      expect(Settings.getCacheUpdated("devices"), isNotNull);
    });

    // Auth._cleanup has no caller without a real identity; the seam runs it.
    test("a logout drops a refresh that is still fetching", () async {
      // The identity package keeps its tokens behind a channel of its own.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              const MethodChannel(
                  'plugins.concerti.io/openidconnect_secure_storage'),
              (call) async => null);
      await _store([deviceJson("d0", "Device 0")]);
      await _devicesOverdue();
      backend.serveDevicesPaged(_devices(2));
      backend.holdDevices = Completer<void>();

      final refresh = CacheHelper.scheduleCacheUpdates();
      await _until(() => requestsTo(_devicesPath) == 1);
      expect(requestsTo(_devicesPath), 1);
      await Auth().cleanupForTest();
      backend.holdDevices!.complete();
      backend.holdDevices = null;
      await refresh;

      final rows = await isar!.deviceInstances.where().findAll();
      expect(rows.map((d) => d.id), ["d0"]);
      expect(Settings.getCacheUpdated("devices"), isNull);
    });
  });

  group("stored notifications", () {
    app.Notification note(String id) =>
        app.Notification("2026-09-30T00:00:00Z", "m", "user", id, false, "t");

    test("an account change drops the stored notifications", () async {
      await NotificationsService.persist([note("n1")], AccountEpoch.current);
      expect(await NotificationsService.loadPersisted(), hasLength(1));

      AppState().notifications
        ..clear()
        ..add(note("n1"));

      await CacheHelper.clearForAccountChange();

      expect(await NotificationsService.loadPersisted(), isEmpty,
          reason: "the offline fallback would show them to the next account");
      expect(AppState().notifications, isEmpty,
          reason: "the next account must not start with the list in memory");
    });

    const notificationsPath = "/notifications-v2/notifications";
    Map<String, dynamic> page(List<String> ids) => {
          "notifications": [for (final id in ids) note(id).toJson()],
          "offset": 0,
          "limit": 10000,
          "total": ids.length,
        };
    final shown = <String>[];

    Future<void> freshStart() async {
      await isar!.writeTxn(() => isar!.notifications.clear());
      addTearDown(() => isar!.writeTxn(() => isar!.notifications.clear()));
      AppState().notifications.clear();
      ErrorReporter.resetForTest();
      shown.clear();
      ErrorReporter.present = shown.add;
    }

    tearDown(() => ErrorReporter.present = (_) {});

    test("a load that fails after an account change shows no stored set",
        () async {
      await freshStart();
      await NotificationsService.persist(
          [note("account-a")], AccountEpoch.current);
      final gate = Completer<void>();
      backend.holds["GET $notificationsPath"] = gate;
      backend.failures["GET $notificationsPath"] =
          DioExceptionType.connectionError;

      final load = AppState().loadNotifications(null);
      await _until(() => requestsTo(notificationsPath) == 1);
      AccountEpoch.advance();
      AppState().notifications.clear();
      gate.complete();
      await load;

      expect(AppState().notifications, isEmpty);
      expect(shown, isEmpty);
    });

    test("a load that succeeds after an account change shows and stores nothing",
        () async {
      await freshStart();
      backend.serveJson("GET", notificationsPath, 200, page(["account-a"]));
      final gate = Completer<void>();
      backend.holds["GET $notificationsPath"] = gate;

      final load = AppState().loadNotifications(null);
      await _until(() => requestsTo(notificationsPath) == 1);
      AccountEpoch.advance();
      gate.complete();
      await load;

      expect(AppState().notifications, isEmpty);
      expect(await NotificationsService.loadPersisted(), isEmpty);
    });

    test("a load that waited across an account change fetches for the new one",
        () async {
      await freshStart();
      backend.serveJson("GET", notificationsPath, 200, page(["n1"]));
      final gate = Completer<void>();
      backend.holds["GET $notificationsPath"] = gate;

      final first = AppState().loadNotifications(null);
      await _until(() => requestsTo(notificationsPath) == 1);
      AccountEpoch.advance();
      final second = AppState().loadNotifications(null);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      gate.complete();
      await Future.wait([first, second]);

      expect(requestsTo(notificationsPath), 2);
      expect(AppState().notifications.map((n) => n.id), ["n1"]);
    });

    test("a load that fails while nobody is signed in shows no stored set",
        () async {
      await freshStart();
      await NotificationsService.persist(
          [note("account-a")], AccountEpoch.current);
      backend.failures["GET $notificationsPath"] =
          DioExceptionType.connectionError;
      Auth().loggedIn = false;
      addTearDown(() => Auth().loggedIn = true);

      await AppState().loadNotifications(null);

      expect(AppState().notifications, isEmpty,
          reason: "the stored set is the last account's, not the user's");
      expect(shown, isEmpty);
    });

    test("notifications fetched before an account change are not stored",
        () async {
      final epoch = AccountEpoch.current;
      AccountEpoch.advance();

      await NotificationsService.persist([note("n2")], epoch);

      expect(await NotificationsService.loadPersisted(), isEmpty);
    });
  });

  group("stored metadata", () {
    test("a fetch from before an account change is not stored", () async {
      final gate = Completer<void>();
      final load = loadMetadataCached<String>('user-device-types', () async {
        await gate.future;
        return [
          {"id": "previous-account-type"}
        ];
      }, (j) => j["id"] as String, maxAge: Duration.zero);

      AccountEpoch.advance();
      await MetadataCache.clear();
      gate.complete();
      await load;
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(await MetadataCache.readEntry('user-device-types'), isNull);
    });

    test("device classes fetched before an account change are not stored",
        () async {
      const path = "/api-aggregator/device-class-uses";
      backend.serveJson("GET", path, 200, {
        "device-classes": [
          {"id": "c1", "name": "Lamps", "image": ""}
        ],
        "used-devices": {},
      });
      final gate = Completer<void>();
      backend.holds["GET $path"] = gate;

      final fetch = DeviceClassesService.getDeviceClasses(fallbackToCache: false);
      await _until(() => requestsTo(path) == 1);
      AccountEpoch.advance();
      await MetadataCache.clear();
      gate.complete();
      await fetch;
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(await MetadataCache.readEntry('device-class-uses'), isNull);
    });
  });

  // One case per entity service that stores what it fetched.
  final writeThrough = <(String, String, Object, Future<void> Function(), Future<int> Function())>[
    (
      "networks",
      "/device-repository/extended-hubs",
      [
        {
          "id": "net-1",
          "name": "Net",
          "hash": "",
          "owner_id": "owner-1",
          "shared": false,
          "device_local_ids": <String>[],
          "device_ids": <String>[],
          "connection_state": "online",
        }
      ],
      () => NetworksService.getNetworks(null, true),
      () => isar!.networks.count(),
    ),
    (
      "locations",
      "/device-repository/locations",
      [
        {
          "id": "location-1",
          "name": "Kitchen",
          "description": "",
          "image": "",
          "device_ids": <String>[],
          "device_group_ids": <String>[],
        }
      ],
      () async => Future.wait(
          await LocationService.getLocations(forceBackend: true)),
      () => isar!.locations.count(),
    ),
    (
      "device groups",
      "/device-repository/device-groups",
      [
        {
          "id": "group-1",
          "name": "Ground floor",
          "image": "",
          "criteria": <Map<String, dynamic>>[],
          "device_ids": <String>[],
          "attributes": null,
        }
      ],
      () async => Future.wait(
          await DeviceGroupsService.getDeviceGroups(forceBackend: true)),
      () => isar!.deviceGroups.count(),
    ),
  ];

  for (final (name, path, body, fetch, count) in writeThrough) {
    test("$name fetched before an account change are not stored", () async {
      await isar!.writeTxn(() async {
        await isar!.networks.clear();
        await isar!.locations.clear();
        await isar!.deviceGroups.clear();
      });
      backend.serveJson("GET", path, 200, body);
      if (name == "device groups") {
        backend.serveJson(
            "GET", "$path/group-1", 200, (body as List).single);
      }
      final gate = Completer<void>();
      backend.holds["GET $path"] = gate;

      final running = fetch();
      await _until(() => requestsTo(path) == 1);
      expect(requestsTo(path), 1);
      AccountEpoch.advance();
      gate.complete();
      await running;

      expect(await count(), 0);
    });
  }

  // One case per save or create that stores the backend's answer.
  final groupJson = {
    "id": "group-1",
    "name": "Ground floor",
    "image": "",
    "criteria": <Map<String, dynamic>>[],
    "device_ids": <String>[],
    "attributes": null,
  };
  final locationJson = {
    "id": "location-1",
    "name": "Kitchen",
    "description": "",
    "image": "",
    "device_ids": <String>[],
    "device_group_ids": <String>[],
  };
  final saves = <(String, String, String, Object, Future<void> Function(), Future<int> Function())>[
    (
      "saveDevice",
      "PUT",
      "/device-manager/devices/d0",
      <String, dynamic>{},
      () => DevicesService.saveDevice(DeviceInstance.fromJson(deviceJson("d0", "Lamp"))),
      () => isar!.deviceInstances.count(),
    ),
    (
      "saveDeviceGroup",
      "PUT",
      "/device-manager/device-groups/group-1",
      groupJson,
      () => DeviceGroupsService.saveDeviceGroup(
          DeviceGroup.fromJson(groupJson), (g) => g.name = "Upstairs"),
      () => isar!.deviceGroups.count(),
    ),
    (
      "createDeviceGroup",
      "POST",
      "/device-manager/device-groups/",
      groupJson,
      () => DeviceGroupsService.createDeviceGroup("Ground floor"),
      () => isar!.deviceGroups.count(),
    ),
    (
      "saveLocation",
      "PUT",
      "/device-manager/locations/location-1",
      locationJson,
      () => LocationService.saveLocation(Location.fromJson(locationJson)),
      () => isar!.locations.count(),
    ),
    (
      "createLocation",
      "POST",
      "/device-manager/locations/",
      locationJson,
      () => LocationService.createLocation("Kitchen"),
      () => isar!.locations.count(),
    ),
  ];

  for (final (name, method, path, body, save, count) in saves) {
    test("$name answered after an account change stores nothing", () async {
      await isar!.writeTxn(() async {
        await isar!.deviceInstances.clear();
        await isar!.deviceGroups.clear();
        await isar!.locations.clear();
      });
      backend.serveJson(method, path, 200, body);
      final gate = Completer<void>();
      backend.holds["$method $path"] = gate;

      final running = save();
      await _until(() => requestsTo(path) == 1);
      expect(requestsTo(path), 1);
      AccountEpoch.advance();
      gate.complete();
      await running;

      expect(await count(), 0);
    });
  }

  final storedNames = <String, (String, Future<String?> Function())>{
    "saveDevice": (
      "Lamp",
      () async => (await isar!.deviceInstances.where().findFirst())?.name
    ),
    "saveDeviceGroup": (
      "Ground floor",
      () async => (await isar!.deviceGroups.where().findFirst())?.name
    ),
    "createDeviceGroup": (
      "Ground floor",
      () async => (await isar!.deviceGroups.where().findFirst())?.name
    ),
    "saveLocation": (
      "Kitchen",
      () async => (await isar!.locations.where().findFirst())?.name
    ),
    "createLocation": (
      "Kitchen",
      () async => (await isar!.locations.where().findFirst())?.name
    ),
  };

  for (final (name, method, path, body, save, count) in saves) {
    test("$name stores the answer for the current account", () async {
      await isar!.writeTxn(() async {
        await isar!.deviceInstances.clear();
        await isar!.deviceGroups.clear();
        await isar!.locations.clear();
      });
      backend.serveJson(method, path, 200, body);

      await save();

      expect(await count(), 1);
      final (expected, read) = storedNames[name]!;
      expect(await read(), expected);
    });
  }

  test("a location created across an account change stays out of the list",
      () async {
    const path = "/device-manager/locations/";
    backend.serveJson("POST", path, 200, locationJson);
    final gate = Completer<void>();
    backend.holds["POST $path"] = gate;
    AppState().locations.clear();

    final create = AppState().createLocation("Kitchen");
    await _until(() => requestsTo(path) == 1);
    AccountEpoch.advance();
    gate.complete();
    final created = await create;

    expect(created.id, "location-1", reason: "the caller still gets it");
    expect(AppState().locations, isEmpty);
  });

  // Last in the file: against a loop that never ends, its refresh stays
  // registered as running and would block every later device refresh.
  test("a refresh of more devices than one page holds ends after the last page",
      () async {
    await _store([]);
    await _devicesOverdue();
    backend.serveDevicesPaged(_devices(6000));

    var done = false;
    try {
      await CacheHelper.scheduleCacheUpdates()
          .timeout(const Duration(seconds: 30));
      done = true;
    } on TimeoutException {
      // Ends a runaway loop through its error path.
      backend.failures["GET $_devicesPath"] = DioExceptionType.connectionError;
    }

    expect(done, isTrue, reason: "the refresh ended");
    expect(requestsTo(_devicesPath), 2);
    expect(await isar!.deviceInstances.count(), 6000);
    expect(Settings.getCacheUpdated("devices"), isNotNull);
  });
}
