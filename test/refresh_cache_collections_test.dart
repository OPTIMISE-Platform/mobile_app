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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/cached_metadata.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/models/exception_log_element.dart';
import 'package:mobile_app/models/location.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/services/device_types.dart';
import 'package:mobile_app/widgets/settings/refresh_cache_tile.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';
import 'test_helper.dart';

FakeBackend _backend({required bool devicesFail}) {
  final backend = FakeBackend();
  backend.serveJson("GET", "/device-repository/device-groups", 200, []);
  backend.serveJson("GET", "/device-repository/extended-hubs", 200, []);
  backend.serveJson("GET", "/device-repository/locations", 200, []);
  backend.serveJson("GET", "/device-repository/v2/device-classes", 200, []);
  for (final path in [
    "/device-repository/functions",
    "/device-repository/aspects",
    "/device-repository/v2/concepts-with-characteristics",
    "/device-repository/characteristics",
  ]) {
    backend.serveJson("GET", path, 200, []);
  }
  if (devicesFail) {
    backend.serveJson(
        "GET", "/device-repository/extended-devices", 500, "boom");
  } else {
    backend.serveDevicesPaged([]);
  }
  return backend;
}

void main() {
  final toasts = <String>[];

  setUpAll(() async {
    await setUpGoldenEnvironment();
    await openTestIsar([
      DeviceInstanceSchema,
      DeviceGroupSchema,
      NetworkSchema,
      LocationSchema,
      CachedMetadataSchema,
      ExceptionLogElementSchema,
    ]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('PonnamKarthik/fluttertoast'), (call) async {
      if (call.method == "showToast") toasts.add(call.arguments["msg"]);
      return true;
    });
  });

  tearDown(() {
    AppState().fetchDeviceTypes =
        (maxAge, {serveStale}) =>
            DeviceTypesService.getDeviceTypes(null, maxAge, serveStale);
    resetAppStateForGolden();
    resetGoldenBackend();
    toasts.clear();
  });

  test("refreshCache reports a collection that could not be refreshed",
      () async {
    serveGoldenBackend(_backend(devicesFail: true));
    expect(await CacheHelper.refreshCache(includeMetadata: false), isFalse);

    serveGoldenBackend(_backend(devicesFail: false));
    expect(await CacheHelper.refreshCache(includeMetadata: false), isTrue);
  });

  testWidgets("the Refresh Cache tile reports a failed device refresh",
      (tester) async {
    serveGoldenBackend(_backend(devicesFail: true));
    AppState().fetchDeviceTypes = (maxAge, {serveStale}) async => <DeviceType>[];
    await pumpGolden(tester, const Scaffold(body: RefreshCacheTile()),
        dark: false);

    // Isar and Hive I/O never completes inside the fake zone of a gesture
    // (docs/testing.md), so the tap's callback runs in runAsync.
    final tile = tester.widget<ListTile>(find.byType(ListTile));
    await tester.runAsync(() async {
      (tile.onTap as dynamic)();
      for (var i = 0; i < 500 && toasts.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });

    expect(toasts, hasLength(1));
    expect(toasts.single, startsWith("Could not refresh cache"));
    await tester.pump();
  });
}
