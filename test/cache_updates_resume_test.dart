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
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/cached_metadata.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/exception_log_element.dart';
import 'package:mobile_app/models/location.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/models/notification.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/shared/isar.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';
import 'test_helper.dart';

const _devicesPath = "/device-repository/extended-devices";

/// Marks every collection as refreshed now, except those in [overdue].
Future<void> _refreshedNow({Set<String> overdue = const {}}) async {
  await Settings.clearCacheUpdated();
  for (final cache in ["devices", "deviceGroups", "networks", "locations"]) {
    if (!overdue.contains(cache)) await Settings.setCacheUpdated(cache);
  }
}

void main() {
  late FakeBackend backend;

  int deviceRequests() =>
      backend.requests.where((r) => r.uri.path == _devicesPath).length;

  setUpAll(() async {
    await setUpGoldenEnvironment();
    await openTestIsar([
      DeviceInstanceSchema,
      DeviceGroupSchema,
      NetworkSchema,
      LocationSchema,
      CachedMetadataSchema,
      ExceptionLogElementSchema,
      NotificationSchema,
    ]);
    await Settings.setFavoritesMoved(true);
    await Settings.setDeviceGroupsCachedWithAspectLists(true);
    Auth().loggedIn = true;
  });

  tearDownAll(() => Auth().loggedIn = false);

  final shown = <String>[];

  setUp(() {
    backend = FakeBackend()..serveDevicesPaged([deviceJson("d1", "Lamp")]);
    for (final path in [
      "/device-repository/device-groups",
      "/device-repository/extended-hubs",
      "/device-repository/locations",
    ]) {
      backend.serveJson("GET", path, 200, []);
    }
    serveGoldenBackend(backend);
    ErrorReporter.resetForTest();
    shown.clear();
    ErrorReporter.present = shown.add;
  });

  tearDown(() {
    resetGoldenBackend();
    ErrorReporter.resetForTest();
    ErrorReporter.present = (_) {};
  });

  group("with every collection current", () {
    setUp(() => _refreshedNow());

    // testWidgets fails on any timer still pending at its end, which is where
    // the old per-collection Future.delayed for the rest of the day showed up.
    testWidgets("scheduling refreshes nothing and arms no timer",
        (tester) async {
      await CacheHelper.scheduleCacheUpdates();
      await tester.pump();
      expect(backend.requests, isEmpty);
    });
  });

  // Not a testWidgets like the case above: Isar I/O started in its fake zone
  // never completes (docs/testing.md), so the zone here records the timers.
  test("refreshing an overdue collection arms no timer either", () async {
    await _refreshedNow(overdue: {"devices"});
    final timers = <Timer>[];

    await runZoned(CacheHelper.scheduleCacheUpdates,
        zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, f) {
        final t = parent.createTimer(zone, duration, f);
        timers.add(t);
        return t;
      },
      createPeriodicTimer: (self, parent, zone, period, f) {
        final t = parent.createPeriodicTimer(zone, period, f);
        timers.add(t);
        return t;
      },
    ));

    expect(deviceRequests(), 1);
    expect(Settings.getCacheUpdated("devices"), isNotNull);
    expect(timers.where((t) => t.isActive), isEmpty,
        reason: "no timer outlives the refresh");
  });

  test("a failed background refresh is logged, an explicit one reported",
      () async {
    await _refreshedNow(overdue: {"devices"});
    backend.failures["GET $_devicesPath"] = DioExceptionType.connectionError;

    await CacheHelper.scheduleCacheUpdates();
    expect(deviceRequests(), 1);
    expect(shown, isEmpty);

    expect(await CacheHelper.refreshCache(includeMetadata: false), isFalse);
    expect(shown, [ErrorReporter.offlineMessage]);
  });

  test("a refresh started before an account change does not land after it",
      () async {
    await _refreshedNow(overdue: {"devices"});
    backend.holdDevices = Completer<void>();
    final previous = CacheHelper.scheduleCacheUpdates();
    for (var i = 0; i < 300 && deviceRequests() == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(deviceRequests(), 1);

    // The held request has already sliced the previous account's list.
    await CacheHelper.switchAccount("next-account");
    final hold = backend.holdDevices!;
    backend.holdDevices = null;
    backend.serveDevicesPaged([deviceJson("d2", "Heater")]);
    expect(await CacheHelper.refreshCache(includeMetadata: false), isTrue);

    hold.complete();
    await previous;

    final rows = await isar!.deviceInstances.where().findAll();
    expect(rows.map((d) => d.id), ["d2"]);
    expect(shown, isEmpty);
  });

  test(
      "a resume refreshes an overdue collection, and a resume while that "
      "refresh runs starts no second one", () async {
    await _refreshedNow(overdue: {"devices"});
    backend.holdDevices = Completer<void>();

    AppState().didChangeAppLifecycleState(AppLifecycleState.resumed);
    for (var i = 0; i < 300 && deviceRequests() == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(deviceRequests(), 1, reason: "the resume started the refresh");

    AppState().didChangeAppLifecycleState(AppLifecycleState.resumed);
    final direct = CacheHelper.scheduleCacheUpdates();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(deviceRequests(), 1);

    backend.holdDevices!.complete();
    backend.holdDevices = null;
    await direct;
    for (var i = 0; i < 300 && Settings.getCacheUpdated("devices") == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(Settings.getCacheUpdated("devices"), isNotNull);

    // Refreshed just now: the next resume has nothing due.
    AppState().didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(deviceRequests(), 1);
  });
}
