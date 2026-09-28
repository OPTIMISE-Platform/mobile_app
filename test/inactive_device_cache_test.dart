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
import 'package:mobile_app/models/location.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/services/devices.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';
import 'test_helper.dart';

DeviceInstance _cached(String id, [String? inactive]) {
  final d = DeviceInstance.fromJson(deviceJson(id, id));
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
    ]);
  });

  tearDown(() async {
    await db.writeTxn(() => db.deviceInstances.clear());
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

    expect(await DevicesService.getCachedInactiveDeviceIds(),
        {"true", "padded"});
  });

  test("a seeded index counts group members without a request", () async {
    await db.writeTxn(() => db.deviceInstances.putAll([
          _cached("a"),
          _cached("b", "true"),
        ]));
    final backend = FakeBackend();
    serveGoldenBackend(backend);

    await AppState().loadInactiveDeviceIds();

    expect(AppState().visibleDeviceCount(["a", "b", "c"]), 2);
    expect(backend.requests, isEmpty);
  });

  test("an account change forgets the previous account's inactive devices",
      () async {
    AppState().noteDevices([_cached("b", "true")]);
    expect(AppState().visibleDeviceCount(["b"]), 0);

    await CacheHelper.clearForAccountChange();

    expect(AppState().visibleDeviceCount(["b"]), 1);
  });
}
