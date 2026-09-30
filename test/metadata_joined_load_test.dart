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

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/mixins/device_mixin.dart';
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/shared/joined_load.dart';

class _State extends ChangeNotifier with DeviceMixin {
  _State() {
    fetchDeviceTypes = (maxAge, {serveStale}) async {
      fetches++;
      final gate = this.gate;
      if (gate != null) await gate.future;
      if (fail) throw Exception("offline");
      return [DeviceType("a", "a", "", "", [], null)];
    };
  }

  int fetches = 0;
  bool fail = false;
  Completer<void>? gate;

  @override
  Future<void> ensureInitialized() async {}
}

void main() {
  setUp(() => ErrorReporter.present = (_) {});
  tearDown(ErrorReporter.resetForTest);

  test("a caller joining a failing load gets the failure, not success",
      () async {
    final load = JoinedLoad();
    final gate = Completer<bool>();
    var runs = 0;
    Future<bool> body() {
      runs++;
      return gate.future;
    }

    final first = load.run(body);
    final joined = load.run(body);
    gate.complete(false);

    expect(await first, isFalse);
    expect(await joined, isFalse);
    expect(runs, 1);
    // A call after the run ended starts a new one.
    expect(await load.run(() async => true), isTrue);
  });

  test("two concurrent device-type loads share one fetch and its failure",
      () async {
    final s = _State()
      ..fail = true
      ..gate = Completer<void>();
    final first = s.loadDeviceTypes();
    final second = s.loadDeviceTypes();
    s.gate!.complete();

    expect(await first, isFalse);
    expect(await second, isFalse);
    expect(s.fetches, 1);
  });

  test(
      "a device-type load arriving while ensureDeviceTypes fails fetches "
      "itself and reports its own outcome", () async {
    final s = _State()
      ..fail = true
      ..gate = Completer<void>();
    // Holds the mutex, then fails and only logs.
    final ensure = s.ensureDeviceTypes(["missing"]);
    await Future<void>.delayed(Duration.zero);
    final load = s.loadDeviceTypes();
    s.gate!.complete();
    await ensure;

    expect(await load, isFalse);
    expect(s.fetches, 2);
  });
}
