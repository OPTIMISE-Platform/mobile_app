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
import 'package:mobile_app/shared/account_epoch.dart';
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

/// Each device-type fetch waits for its own completer in [pending] and
/// returns one type named after [account] as it was when the fetch started.
class _AccountState extends ChangeNotifier with DeviceMixin {
  _AccountState() {
    fetchDeviceTypes = (maxAge, {serveStale}) async {
      final account = this.account;
      final fails = fail;
      final gate = Completer<void>();
      pending.add(gate);
      await gate.future;
      if (fails) throw Exception("offline");
      return [DeviceType(account, account, "", "", [], null)];
    };
    addListener(() => notifications++);
  }

  String account = "a";
  bool fail = false;
  final pending = <Completer<void>>[];
  int notifications = 0;

  /// What a logout does to this state after the epoch moved.
  void changeAccount(String next) {
    AccountEpoch.advance();
    clearDeviceData();
    account = next;
  }

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

  test("a call after an account change starts its own run, and the old run "
      "ending keeps it joinable", () async {
    final load = JoinedLoad();
    final oldGate = Completer<bool>();
    final newGate = Completer<bool>();
    var runs = 0;

    final old = load.run(() {
      runs++;
      return oldGate.future;
    });
    AccountEpoch.advance();
    final current = load.run(() {
      runs++;
      return newGate.future;
    });
    expect(runs, 2, reason: "the old account's run is not joined");

    oldGate.complete(false);
    expect(await old, isFalse);
    final joined = load.run(() async {
      runs++;
      return false;
    });
    expect(runs, 2, reason: "the old run's end must not drop the newer one");
    newGate.complete(true);
    expect(await current, isTrue);
    expect(await joined, isTrue);
  });

  group("device types across an account change", () {
    test("a load that outlives it leaves the map empty, and a call after it "
        "gets its own result", () async {
      final s = _AccountState();
      final old = s.loadDeviceTypes();
      await pumpEventQueue();
      expect(s.pending, hasLength(1));

      s.changeAccount("b");
      s.notifications = 0;
      final current = s.loadDeviceTypes();
      s.pending.single.complete();

      expect(await old, isFalse);
      expect(s.deviceTypes, isEmpty);
      expect(s.notifications, 0);
      await pumpEventQueue();
      expect(s.pending, hasLength(2), reason: "the new call fetched itself");
      s.pending.last.complete();
      expect(await current, isTrue);
      expect(s.deviceTypes.keys, ["b"]);
    });

    test("a load that fails after it reports nothing", () async {
      final s = _AccountState()..fail = true;
      final old = s.loadDeviceTypes();
      await pumpEventQueue();

      s.changeAccount("b");
      s.pending.single.complete();

      expect(await old, isFalse);
      expect(shown, isEmpty);
    });

    test("ensureDeviceTypes outliving it marks no type of the next account "
        "unavailable", () async {
      final s = _AccountState();
      final old = s.ensureDeviceTypes(["missing"]);
      await pumpEventQueue();
      s.changeAccount("b");
      s.pending.single.complete();
      await old;
      expect(s.deviceTypes, isEmpty);

      final current = s.ensureDeviceTypes(["missing"]);
      await pumpEventQueue();
      expect(s.pending, hasLength(2),
          reason: "the old account's answer says nothing about this one");
      s.pending.last.complete();
      await current;
      expect(s.deviceTypes.keys, ["b"]);
    });

    test("ensureDeviceTypes waiting on the mutex across it fetches nothing",
        () async {
      final s = _AccountState();
      final load = s.loadDeviceTypes();
      await pumpEventQueue();
      final ensure = s.ensureDeviceTypes(["missing"]);
      await pumpEventQueue();
      s.changeAccount("b");
      s.pending.single.complete();
      await load;
      await pumpEventQueue();

      expect(s.pending, hasLength(1),
          reason: "the old account's type ids ask nothing of the next one");
      await ensure;
      expect(s.deviceTypes, isEmpty);
    });

    test("ensureDeviceTypes failing after it holds off no retry", () async {
      final s = _AccountState()..fail = true;
      final old = s.ensureDeviceTypes(["missing"]);
      await pumpEventQueue();
      s.changeAccount("b");
      s.pending.single.complete();
      await old;

      s.fail = false;
      final current = s.ensureDeviceTypes(["missing"]);
      await pumpEventQueue();
      expect(s.pending, hasLength(2));
      s.pending.last.complete();
      await current;
      expect(s.deviceTypes.keys, ["b"]);
    });
  });
}
