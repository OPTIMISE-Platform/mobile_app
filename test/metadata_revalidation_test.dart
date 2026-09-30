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
    AppState().fetchDeviceClasses =
        () => DeviceClassesService.getDeviceClasses(fallbackToCache: false);
    AppState().readCachedDeviceClasses =
        DeviceClassesService.getCachedDeviceClasses;
    ErrorReporter.present = (_) {};
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  // One testWidgets for all cases: Dio instances are memoized per process
  // (docs/testing.md), and init runs its loaders through them.
  testWidgets(
      "init serves stale metadata and revalidates it once, after the first "
      "frame", (tester) async {
    final backend = FakeBackend();
    backend.serveJson("GET", "/api-aggregator/device-class-uses", 200,
        {"device-classes": [], "used-devices": {}});
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

    final calls = <(Duration, bool)>[];
    int zeroCalls() => calls.where((c) => c.$1 == Duration.zero).length;
    var storedAt = DateTime.now();
    Completer<void>? revalidationGate;
    Completer<void>? storedGate;
    var zeroFails = false;
    AppState().fetchDeviceTypes = (maxAge, {serveStale}) async {
      calls.add((maxAge, serveStale != null));
      if (maxAge != Duration.zero) {
        await storedGate?.future;
        serveStale?.call(storedAt);
        return [DeviceType("stored", "stored", "", "", [], null)];
      }
      await revalidationGate?.future;
      if (zeroFails) {
        // No timer here: the pass runs partly in the test's fake zone. A
        // runaway loop is stopped after a bound, so a failing run still ends.
        if (zeroCalls() > 20) await Completer<void>().future;
        throw Exception("offline");
      }
      serveStale?.call(DateTime.now());
      return <DeviceType>[];
    };
    final shown = <String>[];
    ErrorReporter.present = shown.add;
    var pushes = 0;
    final sub = AppState().refreshPressed.listen((_) => pushes++);
    addTearDown(sub.cancel);

    Future<void> settle() => tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    // Parts of a pass finish in the fake zone, so a load joining one needs
    // pumps as well as real time to complete.
    Future<void> drive(Future<void> Function() op) async {
      var done = false;
      await tester.runAsync(() async {
        unawaited(op().whenComplete(() => done = true));
      });
      for (var i = 0; i < 300 && !done; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
      expect(done, isTrue, reason: "the operation finished");
    }
    // A pass advances one step per switch between the zones; enough switches
    // for a runaway loop to show.
    Future<void> alternate() async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
    }
    Future<void> waitForCalls(int n) => tester.runAsync(() async {
          for (var i = 0; i < 300 && calls.length < n; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });

    // A current copy: nothing follows the first frame.
    await tester.runAsync(() => AppState().init());
    expect(calls, [(metadataMaxAge, true)]);
    await tester.pump();
    await settle();
    await tester.pump();
    expect(calls, [(metadataMaxAge, true)]);
    expect(pushes, 0);

    await tester.runAsync(() => AppState().onLogout());
    calls.clear();

    // A copy older than metadataMaxAge: served, then fetched fresh once.
    storedAt = DateTime.now().subtract(const Duration(days: 8));
    revalidationGate = Completer<void>();
    await tester.runAsync(() => AppState().init());
    await settle();
    expect(calls, [(metadataMaxAge, true)],
        reason: "nothing is fetched before the first frame");

    await tester.pump();
    await waitForCalls(2);
    expect(calls, [(metadataMaxAge, true), (Duration.zero, true)]);

    // A resume while that fetch is held starts no second one.
    await tester.runAsync(() async {
      AppState().didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    expect(calls, hasLength(2));

    revalidationGate.complete();
    await settle();
    await tester.pump();
    expect(pushes, 1);

    // Revalidated: a later resume has nothing stale to fetch.
    await tester.runAsync(() async {
      AppState().didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(calls, hasLength(2));
    expect(pushes, 1);

    // A stale set whose fresh fetch fails: one fetch per trigger, logged
    // only, and the served copy stays.
    await tester.runAsync(() => AppState().onLogout());
    calls.clear();
    shown.clear();
    zeroFails = true;
    await tester.runAsync(() => AppState().init());
    await tester.pump();
    await alternate();
    expect(zeroCalls(), 1);
    expect(shown, isEmpty);
    expect(AppState().deviceTypes.keys, ["stored"]);

    await tester.runAsync(() async {
      AppState().didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await alternate();
    expect(zeroCalls(), 2);
    expect(shown, isEmpty);
    expect(AppState().deviceTypes.keys, ["stored"]);
    expect(pushes, 1);

    // An account change while the pass runs: it neither notifies nor marks
    // the set fresh, so the next resume fetches it again.
    await tester.runAsync(() => AppState().onLogout());
    calls.clear();
    zeroFails = false;
    revalidationGate = Completer<void>();
    await tester.runAsync(() => AppState().init());
    await tester.pump();
    await waitForCalls(2);
    AccountEpoch.advance();
    revalidationGate.complete();
    revalidationGate = null;
    await settle();
    await tester.pump();
    await settle();
    await tester.pump();
    expect(pushes, 1, reason: "no reload for the gone account");

    await tester.runAsync(() async {
      AppState().didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(zeroCalls(), 2, reason: "the set is still stale");

    // The native pipe's load serves stale like init's, so an init joining it
    // still gets the stale set revalidated.
    await tester.runAsync(() => AppState().onLogout());
    calls.clear();
    zeroFails = false;
    await tester.runAsync(() async {
      storedGate = Completer<void>();
      final pipe = AppState().loadStoredDeviceTypes();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final init = AppState().init();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      storedGate!.complete();
      storedGate = null;
      await Future.wait([pipe, init]);
    });
    expect(calls, [(metadataMaxAge, true)], reason: "init joined the load");
    await tester.pump();
    await waitForCalls(2);
    expect(calls, [(metadataMaxAge, true), (Duration.zero, true)]);
    await settle();
    await tester.pump();

    // The Settings refresh fails on failing device classes, even with a
    // stored copy to fall back to.
    shown.clear();
    AppState().fetchDeviceClasses = () async => throw Exception("offline");
    AppState().readCachedDeviceClasses =
        () async => [DeviceClass("stored", "Stored", "")];
    Object? reloadError;
    await drive(() async {
      try {
        await AppState().reloadMetadata();
      } catch (e) {
        reloadError = e;
      }
    });
    expect(reloadError, isNotNull);
    expect(shown, contains("Could not get device classes"));
    await tester.pump();

    await tester.runAsync(() => AppState().onLogout());
  }, timeout: const Timeout(Duration(minutes: 1)));
}
