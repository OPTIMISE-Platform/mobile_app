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

import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/attribute.dart';
import 'package:mobile_app/models/cached_metadata.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/models/location.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/models/notification.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/services/devices.dart';
import 'package:mobile_app/services/settings.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';
import 'test_helper.dart';

DeviceInstance _cached(String id, [String? inactive, String type = "device-type-1"]) {
  final d = DeviceInstance.fromJson(deviceJson(id, id, deviceTypeId: type));
  if (inactive != null) {
    d.attributes = [Attribute.New(attributeInactive, inactive, null)];
  }
  return d;
}

void main() {
  late Isar db;

  setUpAll(() async {
    await setUpGoldenEnvironment();
    db = await openTestIsar([
      DeviceInstanceSchema,
      DeviceGroupSchema,
      NetworkSchema,
      LocationSchema,
      CachedMetadataSchema,
      NotificationSchema,
    ]);
  });

  tearDown(() async {
    await db.writeTxn(() => db.deviceInstances.clear());
    await Settings.clearCacheUpdated();
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  test("the cache read judges the attribute like DeviceInstance.isInactive",
      () async {
    await db.writeTxn(() => db.deviceInstances.putAll([
          _cached("plain"),
          _cached("true", "true"),
          _cached("padded", " TRUE "),
          _cached("false", "false"),
        ]));

    expect((await DevicesService.getCachedDeviceIndex()).inactive,
        {"true", "padded"});
  });

  test("the cache read pairs every device with its type, and is complete "
      "only after a full refresh", () async {
    await db.writeTxn(() => db.deviceInstances.putAll([
          for (var i = 0; i < 300; i++) _cached("d$i", null, "type-${i % 7}"),
        ]));

    var index = await DevicesService.getCachedDeviceIndex();
    expect(index.deviceTypes, {
      for (var i = 0; i < 300; i++) "d$i": "type-${i % 7}",
    });
    expect(index.complete, isFalse, reason: "no full refresh yet");

    await Settings.setCacheUpdated("devices");
    index = await DevicesService.getCachedDeviceIndex();
    expect(index.complete, isTrue);
  });

  test("a seeded index counts group members without a request", () async {
    await db.writeTxn(() => db.deviceInstances.putAll([
          _cached("a"),
          _cached("b", "true"),
        ]));
    final backend = FakeBackend();
    serveGoldenBackend(backend);

    await AppState().loadDeviceIndex();

    expect(AppState().visibleDeviceCount(["a", "b", "c"]), 2);
    expect(backend.requests, isEmpty);
  });

  test("a seeded index counts class devices once a full refresh filled it",
      () async {
    await db.writeTxn(() => db.deviceInstances.putAll([
          _cached("a", null, "lamp-type"),
          _cached("b", "true", "lamp-type"),
          _cached("h", null, "heater-type"),
        ]));
    AppState().deviceTypes["lamp-type"] =
        DeviceType("lamp-type", "Lamp", "", "lamp", [], null);
    await Settings.setCacheUpdated("devices");

    await AppState().loadDeviceIndex();

    expect(AppState().visibleDeviceCountOfClass("lamp"), 1);
  });

  test("an account change forgets the previous account's inactive devices",
      () async {
    AppState().noteDevices([_cached("b", "true")]);
    expect(AppState().visibleDeviceCount(["b"]), 0);

    await CacheHelper.switchAccount("next-account");

    expect(AppState().visibleDeviceCount(["b"]), 1);
  });

  test("an account change leaves the class counts unknown", () async {
    AppState().deviceTypes["lamp-type"] =
        DeviceType("lamp-type", "Lamp", "", "lamp", [], null);
    AppState().replaceDeviceIndex([_cached("a", null, "lamp-type")]);
    expect(AppState().visibleDeviceCountOfClass("lamp"), 1);

    await CacheHelper.switchAccount("next-account");
    AppState().noteDevices([_cached("n", null, "lamp-type")]);

    expect(AppState().visibleDeviceCountOfClass("lamp"), isNull);
  });
}
