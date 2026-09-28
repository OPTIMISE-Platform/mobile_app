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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/services/device_types.dart';
import 'package:mobile_app/widgets/settings/refresh_cache_tile.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

void main() {
  final toasts = <String>[];

  setUpAll(() async {
    await setUpGoldenEnvironment();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('PonnamKarthik/fluttertoast'), (call) async {
      if (call.method == "showToast") toasts.add(call.arguments["msg"]);
      return true;
    });
  });

  tearDown(() {
    AppState().fetchDeviceTypes =
        (maxAge) => DeviceTypesService.getDeviceTypes(null, maxAge);
    resetAppStateForGolden();
    resetGoldenBackend();
    toasts.clear();
  });

  testWidgets(
      "a device-type reload that fails while the refresh runs is reported "
      "as a failed refresh", (tester) async {
    final backend = FakeBackend();
    backend.serveJson("GET", "/api-aggregator/device-class-uses", 200,
        {"device-classes": [], "used-devices": {}});
    for (final path in [
      "/device-repository/functions",
      "/device-repository/aspects",
      "/device-repository/v2/concepts-with-characteristics",
      "/device-repository/characteristics",
    ]) {
      backend.serveJson("GET", path, 200, []);
    }
    serveGoldenBackend(backend);

    var failTypes = false;
    Completer<void>? typesGate;
    AppState().fetchDeviceTypes = (maxAge) async {
      final gate = typesGate;
      if (gate != null) await gate.future;
      if (failTypes) throw Exception("device types unreachable");
      return <DeviceType>[];
    };

    await pumpGolden(tester, const Scaffold(body: RefreshCacheTile()),
        dark: false);

    // Clearing the cache writes to Hive, which never completes inside the
    // fake zone of a gesture (docs/testing.md): run the tap's callback in
    // runAsync instead.
    Future<void> refresh() => tester.runAsync(() async {
          final tile = tester.widget<ListTile>(find.byType(ListTile));
          (tile.onTap as dynamic)();
          for (var i = 0; i < 300 && toasts.isEmpty; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });

    // Control: everything answers, the refresh reports success.
    await refresh();
    expect(toasts, ["Cache refreshed"]);
    toasts.clear();
    await tester.pump();

    // A type reload for a device page is running when the refresh starts, and
    // it fails.
    failTypes = true;
    final tile = tester.widget<ListTile>(find.byType(ListTile));
    // Gate and load are created inside runAsync as well: a future from the
    // fake zone delivers its result there, which nothing pumps meanwhile.
    await tester.runAsync(() async {
      typesGate = Completer<void>();
      final ensure = AppState().ensureDeviceTypes(["unknown-type"]);
      await Future<void>.delayed(Duration.zero);
      (tile.onTap as dynamic)();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      typesGate!.complete();
      await ensure;
      for (var i = 0; i < 300 && toasts.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });

    expect(toasts, hasLength(1));
    expect(toasts.single, startsWith("Could not refresh cache"));
    await tester.pump();
  });
}
