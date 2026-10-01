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
import 'package:mobile_app/widgets/tabs/classes/device_class.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

// One testWidgets for all cases: a second one in the same process may not
// get its requests answered (docs/testing.md).
void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  testWidgets(
      "the Classes list shows the classes of the user's device types, counts "
      "them from the device index and lists a class's devices on tap",
      (tester) async {
    await warmUpMgwStorage(tester);
    final backend = FakeBackend();
    backend.serveJson("GET", "/device-repository/device-groups", 200, []);
    backend.serveJson("GET", "/device-repository/extended-hubs", 200, []);
    backend.serveJson("GET", "/device-repository/locations", 200, []);
    for (final path in [
      "/device-repository/functions",
      "/device-repository/aspects",
      "/device-repository/v2/concepts-with-characteristics",
      "/device-repository/characteristics",
    ]) {
      backend.serveJson("GET", path, 200, []);
    }
    final types = [
      deviceTypeJson("lamp-type", deviceClassId: "lamp"),
      deviceTypeJson("heater-type", deviceClassId: "heating"),
    ];
    backend.serveJson(
        "GET", "/device-repository/user-device-types", 200, types);
    backend.serveJson("GET", "/device-repository/v2/device-classes", 200, [
      deviceClassJson("heating", "Heating"),
      deviceClassJson("lamp", "Lamps"),
      deviceClassJson("sensors", "Sensors"),
    ]);
    final devices = [
      deviceJson("lamp-1", "Kitchen lamp", deviceTypeId: "lamp-type"),
      deviceJson("lamp-2", "Hall lamp", deviceTypeId: "lamp-type"),
      deviceJson("lamp-3", "Old lamp",
          deviceTypeId: "lamp-type", inactive: true),
      deviceJson("heater-1", "Heat pump", deviceTypeId: "heater-type"),
    ];
    backend.serveDevicesPaged(devices);
    serveGoldenBackend(backend);

    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    await tester.runAsync(() => AppState().init());
    await pumpGolden(tester, const Scaffold(body: DeviceListByDeviceClass()),
        dark: false);
    await settle();

    // Classes without a device type of the user stay off the list.
    expect(find.text("Lamps"), findsOneWidget);
    expect(find.text("Heating"), findsOneWidget);
    expect(find.text("Sensors"), findsNothing);
    // Pages seen are not all devices: no count rather than a low one.
    expect(find.textContaining("Device"), findsNothing);

    // The full device refresh fills the index; inactive devices are hidden.
    AppState().replaceDeviceIndex(devices.map(DeviceInstance.fromJson));
    await settle();
    expect(find.text("2 Devices"), findsOneWidget, reason: "lamps");
    expect(find.text("1 Device"), findsOneWidget, reason: "heating");

    // A device of a type not loaded yet reloads the types, and its class
    // comes onto the list.
    devices.add(
        deviceJson("sensor-1", "Window sensor", deviceTypeId: "sensor-type"));
    backend.serveJson("GET", "/device-repository/user-device-types", 200, [
      ...types,
      deviceTypeJson("sensor-type", deviceClassId: "sensors"),
    ]);
    AppState().replaceDeviceIndex(devices.map(DeviceInstance.fromJson));
    await settle();
    expect(find.text("Sensors"), findsOneWidget);
    expect(find.text("1 Device"), findsNWidgets(2), reason: "heating, sensors");

    // Pulling the list refetches classes, types and devices: a device of a
    // new class added elsewhere shows with its count.
    devices.add(deviceJson("door-1", "Front door", deviceTypeId: "door-type"));
    backend.serveJson("GET", "/device-repository/user-device-types", 200, [
      ...types,
      deviceTypeJson("sensor-type", deviceClassId: "sensors"),
      deviceTypeJson("door-type", deviceClassId: "doors"),
    ]);
    backend.serveJson("GET", "/device-repository/v2/device-classes", 200, [
      deviceClassJson("doors", "Doors"),
      deviceClassJson("heating", "Heating"),
      deviceClassJson("lamp", "Lamps"),
      deviceClassJson("sensors", "Sensors"),
    ]);
    await tester.runAsync(() => AppState().reloadDeviceClasses());
    await settle();
    expect(find.text("Doors"), findsOneWidget);
    expect(find.text("1 Device"), findsNWidgets(3),
        reason: "doors, heating, sensors");

    // Tapping a class lists its devices, found by their device types.
    await tester.tap(find.text("Lamps"));
    await settle();
    expect(find.text("Kitchen lamp"), findsOneWidget);
    expect(find.text("Hall lamp"), findsOneWidget);
    expect(find.text("Old lamp"), findsNothing, reason: "inactive");
    expect(find.text("Heat pump"), findsNothing);
    expect(find.text("Window sensor"), findsNothing);
    // The page request (limit 50), not the by-id status refresh after it.
    final page = backend.requests.lastWhere((r) =>
        r.uri.path == "/device-repository/extended-devices" &&
        r.uri.queryParameters["limit"] == "50");
    expect(page.uri.queryParameters["device-type-ids"], "lamp-type");
    expect(page.uri.queryParameters.containsKey("ids"), isFalse);
    await settle();
  });
}
