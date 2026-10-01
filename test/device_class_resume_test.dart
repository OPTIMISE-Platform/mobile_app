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


import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/services/device_classes.dart';
import 'package:mobile_app/services/device_types.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/widgets/tabs/classes/device_class.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    AppState().fetchDeviceTypes = (maxAge, {serveStale}) =>
        DeviceTypesService.getDeviceTypes(null, maxAge, serveStale);
    AppState().fetchDeviceClasses = (maxAge, {serveStale}) =>
        DeviceClassesService.getDeviceClasses(
            maxAge: maxAge, serveStale: serveStale);
    ErrorReporter.present = (_) {};
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  testWidgets("one resume with the Classes tab open retries the classes once",
      (tester) async {
    final backend = FakeBackend();
    for (final path in [
      "/device-repository/functions",
      "/device-repository/aspects",
      "/device-repository/v2/concepts-with-characteristics",
      "/device-repository/characteristics",
      "/device-repository/locations",
    ]) {
      backend.serveJson("GET", path, 200, []);
    }
    serveGoldenBackend(backend);
    await warmUpMgwStorage(tester);
    AppState().fetchDeviceTypes = (maxAge, {serveStale}) async {
      serveStale?.call(DateTime.now());
      return [];
    };
    var classFetches = 0;
    AppState().fetchDeviceClasses = (maxAge, {serveStale}) async {
      classFetches++;
      throw Exception("offline");
    };
    ErrorReporter.present = (_) {};

    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
    }

    await tester.runAsync(() => AppState().init());
    await pumpGolden(tester, const Scaffold(body: DeviceListByDeviceClass()),
        dark: false);
    await settle();
    expect(classFetches, 2, reason: "init, and opening the tab without classes");

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle();
    expect(classFetches, 3);

    await tester.runAsync(() => AppState().onLogout());
  });
}
