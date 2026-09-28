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
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/widgets/shared/slice_position.dart';
import 'package:mobile_app/widgets/tabs/shared/device_list_item.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  testWidgets(
      "a device row shows its location after app init, without visiting the Locations tab",
      (tester) async {
    final backend = FakeBackend();
    backend.serveJson("GET", "/device-repository/locations", 200, [
      {
        "id": "location-1",
        "name": "Kitchen",
        "description": "",
        "image": "",
        "device_ids": ["device-1"],
        "device_group_ids": [],
      }
    ]);
    // Every other metadata call AppState.init() makes falls through to
    // FakeBackend's 404 default - already tolerated, each loader reports and
    // swallows its own error.
    serveGoldenBackend(backend);
    await warmUpMgwStorage(tester);

    // AppState.init() itself only awaits the *other* loaders; loadLocations()
    // runs unawaited alongside them (see AppState.init()'s doc comment), so
    // this also waits for that fire-and-forget call to actually finish
    // before pumping a row that depends on its result. init() and
    // loadLocations() both do real Dio I/O (through FakeBackend, not the
    // network, but still real async work), hence runAsync.
    await tester.runAsync(() async {
      await AppState().init();
      var waited = Duration.zero;
      while (AppState().loadingLocations() && waited < const Duration(seconds: 5)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        waited += const Duration(milliseconds: 10);
      }
    });

    expect(AppState().locations.map((l) => l.name), contains("Kitchen"));

    final d = DeviceInstance(
      "device-1",
      "device-1-local",
      "Living room lamp",
      null,
      "device-type-1",
      false,
      "owner-1",
      "Living room lamp",
      DeviceConnectionStatus.online,
    );
    await pumpGolden(
      tester,
      Scaffold(body: DeviceListItem(d, null, position: SlicePosition.only)),
      dark: false,
    );

    expect(find.text("Kitchen"), findsOneWidget);
  });
}
