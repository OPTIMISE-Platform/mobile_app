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
import 'package:mobile_app/services/device_classes.dart';
import 'package:mobile_app/services/device_types.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/shared/metadata_cache.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

void main() {
  final shown = <String>[];
  final classCalls = <Duration>[];
  var fail = false;
  Completer<void>? gate;

  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  setUp(() {
    shown.clear();
    classCalls.clear();
    fail = false;
    gate = null;
    ErrorReporter.present = shown.add;
    // Each report past the window that hides a repeated message.
    var now = DateTime(2026);
    ErrorReporter.clock = () => now = now.add(const Duration(minutes: 1));
    serveGoldenBackend(FakeBackend()..serveDevicesPaged([]));
    AppState().fetchDeviceTypes = (maxAge, {serveStale}) async => [];
    AppState().fetchDeviceClasses = (maxAge, {serveStale}) async {
      classCalls.add(maxAge);
      final g = gate;
      if (g != null) await g.future;
      if (fail) throw Exception("offline");
      return [DeviceClass("lamp", "Lamps", "")];
    };
  });

  tearDown(() {
    AppState().fetchDeviceTypes = (maxAge, {serveStale}) =>
        DeviceTypesService.getDeviceTypes(null, maxAge, serveStale);
    AppState().fetchDeviceClasses = (maxAge, {serveStale}) =>
        DeviceClassesService.getDeviceClasses(
            maxAge: maxAge, serveStale: serveStale);
    ErrorReporter.resetForTest();
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  test("a pull that joins a quiet load from the store fetches fresh after it, "
      "and reports that fetch's failure", () async {
    gate = Completer<void>();
    final background = AppState().loadDeviceClasses(quiet: true);
    final pull = AppState().reloadDeviceClasses();
    await pumpEventQueue();
    fail = true;
    gate!.complete();
    gate = null;
    await Future.wait([background, pull]);

    expect(classCalls, [metadataMaxAge, Duration.zero]);
    expect(shown, ["Could not get device classes"]);
  });

  test("a pull that joins a fresh, reported load does not fetch again nor "
      "report twice", () async {
    gate = Completer<void>();
    fail = true;
    final explicit = AppState().loadDeviceClasses(maxAge: Duration.zero);
    final pull = AppState().reloadDeviceClasses();
    await pumpEventQueue();
    gate!.complete();
    gate = null;
    await Future.wait([explicit, pull]);

    expect(classCalls, [Duration.zero]);
    expect(shown, ["Could not get device classes"]);
  });
}
