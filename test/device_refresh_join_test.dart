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
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/shared/error_reporter.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

const _path = "/device-repository/extended-devices";

void main() {
  final shown = <String>[];

  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  setUp(() {
    shown.clear();
    ErrorReporter.present = shown.add;
    // Every report past the window that hides a repeated message, so a
    // second report of the same failure shows.
    var now = DateTime(2026);
    ErrorReporter.clock = () => now = now.add(const Duration(minutes: 1));
  });

  tearDown(() {
    ErrorReporter.resetForTest();
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  int fetches(FakeBackend backend) =>
      backend.requests.where((r) => r.uri.path == _path).length;

  test("a pull joins a running device refresh instead of starting another",
      () async {
    final backend = FakeBackend()
      ..serveJson("GET", _path, 200, [deviceJson("d1", "Lamp")]);
    final gate = Completer<void>();
    backend.holds["GET $_path"] = gate;
    serveGoldenBackend(backend);

    final background = CacheHelper.refreshDevicesInBackgroundForTest();
    final pull = CacheHelper.refreshDevicesNow();
    final second = CacheHelper.refreshDevicesNow();
    await pumpEventQueue();
    gate.complete();

    expect(await Future.wait([background, pull, second]), [true, true, true]);
    expect(fetches(backend), 1);

    // Once it has ended, the next pull fetches again.
    backend.holds.clear();
    expect(await CacheHelper.refreshDevicesNow(), isTrue);
    expect(fetches(backend), 2);
  });

  test("a pull that joined a quiet refresh still reports its failure",
      () async {
    final backend = FakeBackend()..serveJson("GET", _path, 500, "boom");
    final gate = Completer<void>();
    backend.holds["GET $_path"] = gate;
    serveGoldenBackend(backend);

    final background = CacheHelper.refreshDevicesInBackgroundForTest();
    final pull = CacheHelper.refreshDevicesNow();
    await pumpEventQueue();
    gate.complete();

    expect(await background, isFalse);
    expect(await pull, isFalse);
    expect(fetches(backend), 1);
    expect(shown, hasLength(1), reason: "the quiet run only logged");
  });

  test("a pull alongside an explicit refresh does not report twice", () async {
    final backend = FakeBackend()..serveJson("GET", _path, 500, "boom");
    final gate = Completer<void>();
    backend.holds["GET $_path"] = gate;
    serveGoldenBackend(backend);

    final first = CacheHelper.refreshDevicesNow();
    final second = CacheHelper.refreshDevicesNow();
    await pumpEventQueue();
    gate.complete();

    expect(await Future.wait([first, second]), [false, false]);
    expect(fetches(backend), 1);
    expect(shown, hasLength(1));
  });
}
