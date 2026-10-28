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
import 'package:mobile_app/mixins/resume_refresh_mixin.dart';
import 'package:mobile_app/services/api_available.dart';
import 'package:mobile_app/services/device_classes.dart';
import 'package:mobile_app/services/device_types.dart';
import 'package:mobile_app/shared/metadata_cache.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

class _Reloading extends StatefulWidget {
  const _Reloading(this.onReload);

  final VoidCallback onReload;

  @override
  State<_Reloading> createState() => _ReloadingState();
}

class _ReloadingState extends State<_Reloading> with ResumeRefreshMixin {
  @override
  void onResumed() => widget.onReload();

  @override
  Widget build(BuildContext context) => const SizedBox();
}

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
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  // One testWidgets for every case, as in metadata_retry_test.dart.
  testWidgets("the platform found again reloads once, as a resume does",
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
    // The classes cannot be loaded, so every reload retries them once.
    final classCalls = <Duration>[];
    AppState().fetchDeviceClasses = (maxAge, {serveStale}) async {
      classCalls.add(maxAge);
      throw Exception("offline");
    };
    var reloads = 0;
    await tester.pumpWidget(MaterialApp(home: _Reloading(() => reloads++)));

    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
    }

    await tester.runAsync(() => AppState().init());
    await settle();
    expect(classCalls, [metadataMaxAge]);

    // The recheck timer finds the platform.
    ApiAvailableService.probeOverride = () async => true;
    await tester.runAsync(() async {
      ApiAvailableService().markPlatformUnreachable();
      await ApiAvailableService().recheckPlatform();
    });
    await settle();
    expect(classCalls, [metadataMaxAge, Duration.zero]);
    expect(reloads, 1, reason: "the screen on top reloads too");

    // A resume whose probe finds it reloads once, not once for each.
    Future<void> resume() => tester.runAsync(() async {
          tester.binding
            ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
            ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        });

    await tester.runAsync(
        () async => ApiAvailableService().markPlatformUnreachable());
    await resume();
    await settle();
    expect(classCalls, [metadataMaxAge, Duration.zero, Duration.zero]);
    expect(reloads, 3, reason: "on the resume, then on the platform found");

    // A resume while it is reachable reloads as before.
    await resume();
    await settle();
    expect(classCalls, hasLength(4));
    expect(reloads, 4);

    // Found in the background: the resume refreshes, once.
    await tester.runAsync(() async {
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
        ..handleAppLifecycleStateChanged(AppLifecycleState.paused);
      ApiAvailableService().markPlatformUnreachable();
      await ApiAvailableService().recheckPlatform();
    });
    await settle();
    expect(classCalls, hasLength(4), reason: "nothing loads in the background");
    expect(reloads, 4);

    await tester.runAsync(() async {
      tester.binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    await settle();
    expect(classCalls, hasLength(5));
    expect(reloads, 5);
  });
}
