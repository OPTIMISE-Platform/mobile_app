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

import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/cached_metadata.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/models/location.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/models/notification.dart';
import 'package:mobile_app/services/settings.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';
import 'test_helper.dart';

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

  test("a device the cache calls offline shows no state until the refresh answers", () async {
    await db.writeTxn(() => db.deviceInstances
        .put(DeviceInstance.fromJson(deviceJson("fan", "Fan", connectionState: "offline"))));
    final backend = FakeBackend();
    backend.serveJson("GET", "/device-repository/device-groups", 200, []);
    backend.serveJson("GET", "/device-repository/extended-hubs", 200, []);
    backend.serveJson("GET", "/device-repository/device-types", 200, []);
    backend.serveJson("GET", "/device-repository/user-device-types", 200, []);
    backend.serveDevicesPaged([deviceJson("fan", "Fan")]);
    // The connection refresh, held so the list is seen before it answers.
    final refresh = Completer<void>();
    backend.holds["GET /device-repository/extended-devices"] = refresh;
    serveGoldenBackend(backend);

    await AppState().searchDevices(DeviceSearchFilter.empty(), true);

    expect(AppState().devices.single.connection_state, DeviceConnectionStatus.unknown,
        reason: "the cached offline showed as a chip the refresh then took back");

    refresh.complete();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(AppState().devices.single.connection_state, DeviceConnectionStatus.online);
  });
}
