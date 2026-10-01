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
import 'package:mobile_app/models/device_class.dart';
import 'package:mobile_app/shared/account_epoch.dart';
import 'package:mobile_app/shared/error_reporter.dart';

class _State extends ChangeNotifier with DeviceMixin {
  _State() {
    fetchDeviceClasses = () async {
      fetches++;
      final name = fetchedName;
      final gate = this.gate;
      if (gate != null) await gate.future;
      if (fail) throw Exception("offline");
      return [DeviceClass(name, name, "")];
    };
    readCachedDeviceClasses = () async {
      reads++;
      await readGate?.future;
      return stored ? [DeviceClass("stored", "Stored", "")] : null;
    };
    addListener(() => notifications++);
  }

  bool stored = true;
  bool fail = false;

  /// The id the next fetch returns, read when it starts.
  String fetchedName = "fresh";
  Completer<void>? gate;
  Completer<void>? readGate;
  int fetches = 0;
  int reads = 0;
  int notifications = 0;

  @override
  Future<void> ensureInitialized() async {}
}

void main() {
  final shown = <String>[];

  setUp(() {
    shown.clear();
    ErrorReporter.present = shown.add;
  });
  tearDown(ErrorReporter.resetForTest);

  test("a stored copy is served without asking the backend", () async {
    final s = _State();

    expect(await s.loadCachedDeviceClasses(), isTrue);
    expect(s.deviceClasses.keys, ["stored"]);
    expect(s.deviceClassesFromCache, isTrue);
    expect(s.fetches, 0);
  });

  test("with nothing stored the load waits for the backend", () async {
    final s = _State()..stored = false;

    expect(await s.loadCachedDeviceClasses(), isTrue);
    expect(s.deviceClasses.keys, ["fresh"]);
    expect(s.deviceClassesFromCache, isFalse);
    expect(s.fetches, 1);
  });

  test("a background refetch swaps on success and notifies", () async {
    final s = _State();
    await s.loadCachedDeviceClasses();
    s.notifications = 0;

    expect(await s.refetchDeviceClasses(), isTrue);
    expect(s.deviceClasses.keys, ["fresh"]);
    expect(s.deviceClassesFromCache, isFalse);
    expect(s.notifications, 1);
  });

  test("a failed background refetch keeps the copy and shows nothing",
      () async {
    final s = _State();
    await s.loadCachedDeviceClasses();
    s.fail = true;

    s.reads = 0;

    expect(await s.refetchDeviceClasses(), isFalse);
    expect(s.deviceClasses.keys, ["stored"]);
    expect(s.deviceClassesFromCache, isTrue);
    expect(shown, isEmpty);
    expect(s.reads, 0, reason: "no fallback: that would pass as success");
  });

  test("without fallback a failed fetch reports although a copy is stored",
      () async {
    final s = _State();
    await s.loadCachedDeviceClasses();
    s.fail = true;
    s.reads = 0;

    expect(await s.loadDeviceClasses(fallbackToCache: false), isFalse);
    expect(shown, ["Could not get device classes"]);
    expect(s.reads, 0);
    expect(s.deviceClasses.keys, ["stored"], reason: "the list stays");
  });

  test("a fetch that falls back to the stored copy counts as that copy",
      () async {
    final s = _State();
    await s.loadCachedDeviceClasses();
    await s.refetchDeviceClasses();
    expect(s.deviceClassesFromCache, isFalse);
    s.fail = true;

    expect(await s.loadDeviceClasses(), isTrue);
    expect(s.deviceClasses.keys, ["stored"]);
    expect(s.deviceClassesFromCache, isTrue);
    expect(shown, isEmpty);
  });

  test("a background refetch keeps the list out of the loading state",
      () async {
    final s = _State();
    await s.loadCachedDeviceClasses();
    s.gate = Completer<void>();

    final refetch = s.refetchDeviceClasses();
    await pumpEventQueue();
    expect(s.fetches, 1, reason: "the fetch is in flight");
    expect(s.loadingDeviceClasses, isFalse);
    s.gate!.complete();
    await refetch;
  });

  group("across an account change", () {
    void changeAccount(_State s) {
      AccountEpoch.advance();
      s.clearDeviceData();
      s.fetchedName = "next";
    }

    test("a load that outlives it leaves the map empty, and a call after it "
        "gets its own result", () async {
      final s = _State()..gate = Completer<void>();
      final old = s.loadDeviceClasses();
      await pumpEventQueue();
      expect(s.fetches, 1);

      changeAccount(s);
      final oldGate = s.gate!;
      s.gate = Completer<void>();
      s.notifications = 0;
      final current = s.loadDeviceClasses();
      oldGate.complete();

      expect(await old, isFalse);
      expect(s.deviceClasses, isEmpty);
      expect(s.notifications, 0);
      await pumpEventQueue();
      expect(s.fetches, 2, reason: "the new call fetched itself");
      s.gate!.complete();
      expect(await current, isTrue);
      expect(s.deviceClasses.keys, ["next"]);
    });

    test("a fetch that fails after it neither serves the stored copy nor "
        "reports", () async {
      final s = _State()
        ..fail = true
        ..gate = Completer<void>();
      final old = s.loadDeviceClasses();
      await pumpEventQueue();

      changeAccount(s);
      s.gate!.complete();

      expect(await old, isFalse);
      expect(s.deviceClasses, isEmpty);
      expect(s.reads, 0, reason: "the stored copy is the gone account's");
      expect(shown, isEmpty);
    });

    test("a stored copy read across it is not served", () async {
      final s = _State()
        ..fail = true
        ..readGate = Completer<void>();
      final old = s.loadDeviceClasses();
      await pumpEventQueue();
      expect(s.reads, 1, reason: "the failed fetch fell back to the store");

      changeAccount(s);
      s.readGate!.complete();

      expect(await old, isFalse);
      expect(s.deviceClasses, isEmpty);
      expect(shown, isEmpty);
    });

    test("a background refetch that outlives it leaves the map empty",
        () async {
      final s = _State()..gate = Completer<void>();
      final old = s.refetchDeviceClasses();
      await pumpEventQueue();

      changeAccount(s);
      s.notifications = 0;
      s.gate!.complete();

      expect(await old, isFalse);
      expect(s.deviceClasses, isEmpty);
      expect(s.notifications, 0);
    });
  });
}
