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

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_class.dart';
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/services/device_classes.dart';
import 'package:mobile_app/services/device_types.dart';
import 'package:mobile_app/shared/account_epoch.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/shared/metadata_cache.dart';

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

  // One testWidgets for all cases: Dio instances are memoized per process
  // (docs/testing.md), and init runs its loaders through them.
  testWidgets("a metadata set whose load failed is retried on resume",
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

    var typesStoredAt = DateTime.now();
    var types = <DeviceType>[];
    Completer<void>? typesGate;
    var typeCalls = 0;
    AppState().fetchDeviceTypes = (maxAge, {serveStale}) async {
      typeCalls++;
      if (maxAge == Duration.zero) await typesGate?.future;
      serveStale?.call(maxAge == Duration.zero ? DateTime.now() : typesStoredAt);
      return types;
    };
    final classCalls = <Duration>[];
    var classesFail = true;
    Completer<void>? classGate;
    DateTime? classesStoredAt;
    var throwingImage = false;
    AppState().fetchDeviceClasses = (maxAge, {serveStale}) async {
      classCalls.add(maxAge);
      if (maxAge == Duration.zero) await classGate?.future;
      if (classesFail) throw Exception("offline");
      serveStale?.call(classesStoredAt ?? DateTime.now());
      return [
        throwingImage ? _ThrowingImage("lamp") : DeviceClass("lamp", "Lamps", "")
      ];
    };
    final shown = <String>[];
    ErrorReporter.present = shown.add;

    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
    }

    Future<void> resume() async {
      await tester.runAsync(() async {
        AppState().didChangeAppLifecycleState(AppLifecycleState.resumed);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await settle();
    }

    // An offline first start: the classes load fails, the others succeed.
    await tester.runAsync(() => AppState().init());
    await settle();
    expect(classCalls, [metadataMaxAge]);
    expect(AppState().deviceClasses, isEmpty);
    shown.clear();

    // The pass after the first frame leaves a failed set alone; a resume
    // retries it, quietly while it still fails.
    await resume();
    expect(classCalls, [metadataMaxAge, Duration.zero]);
    expect(shown, isEmpty);

    classesFail = false;
    await resume();
    expect(classCalls, hasLength(3));
    expect(AppState().deviceClasses.keys, ["lamp"]);

    // Loaded now, with its time recorded: the next resume has nothing due.
    await resume();
    expect(classCalls, hasLength(3));

    // A retry asked for while a pass runs is taken up by that pass.
    await tester.runAsync(() => AppState().onLogout());
    classCalls.clear();
    classesFail = true;
    typesStoredAt = DateTime.now().subtract(const Duration(days: 8));
    typesGate = Completer<void>();
    await tester.runAsync(() => AppState().init());
    await settle();
    expect(classCalls, [metadataMaxAge]);
    expect(typeCalls, greaterThanOrEqualTo(2), reason: "the stale pass runs");
    classesFail = false;
    await tester.runAsync(() async {
      unawaited(AppState().retryFailedMetadata());
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    expect(classCalls, [metadataMaxAge], reason: "the pass is held");
    typesGate.complete();
    typesGate = null;
    await settle();
    expect(classCalls, [metadataMaxAge, Duration.zero]);
    expect(AppState().deviceClasses.keys, ["lamp"]);

    // A request while the pass retries a set: that pass tries it once more,
    // and no further without another request.
    await tester.runAsync(() => AppState().onLogout());
    classCalls.clear();
    classesFail = true;
    typesStoredAt = DateTime.now();
    await tester.runAsync(() => AppState().init());
    await settle();
    classGate = Completer<void>();
    await tester.runAsync(() async {
      unawaited(AppState().retryFailedMetadata());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      unawaited(AppState().retryFailedMetadata());
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    expect(classCalls, [metadataMaxAge, Duration.zero]);
    classGate.complete();
    classGate = null;
    await settle();
    expect(classCalls, [metadataMaxAge, Duration.zero, Duration.zero]);
    await settle();
    expect(classCalls, hasLength(3), reason: "no loop on a failing set");

    // A pass that outlives the account leaves the next account's request to
    // a pass of its own.
    classGate = Completer<void>();
    await tester.runAsync(() async {
      unawaited(AppState().retryFailedMetadata());
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    expect(classCalls, hasLength(4), reason: "held");
    // The account changes; nothing else of the change is needed here.
    AccountEpoch.advance();
    final oldGate = classGate;
    classGate = null;
    classesFail = false;
    await tester.runAsync(() async {
      unawaited(AppState().retryFailedMetadata());
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    expect(AppState().deviceClasses, isEmpty,
        reason: "the old pass still runs, so the request waits");
    oldGate.complete();
    await settle();
    expect(AppState().deviceClasses.keys, ["lamp"]);

    // A loader that throws ends the pass, and its request with it: no pass
    // follows on its own.
    await tester.runAsync(() => AppState().onLogout());
    classesFail = false;
    classesStoredAt = DateTime.now().subtract(const Duration(days: 8));
    types = [DeviceType("t", "t", "", "lamp", [], null)];
    await tester.runAsync(() => AppState().init());
    await settle();
    throwingImage = true;
    final before = classCalls.length;
    Object? thrown;
    await tester.runAsync(() async {
      try {
        await AppState().retryFailedMetadata();
      } catch (e) {
        thrown = e;
      }
    });
    expect(thrown, isA<StateError>());
    expect(classCalls, hasLength(before + 1));
    throwingImage = false;
    await settle();
    expect(classCalls, hasLength(before + 1));

    await tester.runAsync(() => AppState().onLogout());
  }, timeout: const Timeout(Duration(minutes: 1)));
}

/// Stands for a loader that throws: the class load runs into it after its
/// fetch.
class _ThrowingImage extends DeviceClass {
  _ThrowingImage(String id) : super(id, id, "");

  @override
  void loadImage() => throw StateError("image");
}
