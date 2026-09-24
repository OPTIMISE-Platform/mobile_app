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

@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_class.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/widgets/tabs/classes/device_class.dart';
import 'package:mobile_app/widgets/tabs/devices/device_list.dart';
import 'package:mobile_app/widgets/tabs/groups/group_list.dart';
import 'package:mobile_app/widgets/tabs/networks/device_networks.dart';

import 'golden_helper.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
  });

  Widget tabScreen(Widget child) => Scaffold(body: child);

  for (final dark in [false, true]) {
    final suffix = dark ? "dark" : "light";

    testWidgets("groups list ($suffix)", (tester) async {
      AppState().deviceGroups.addAll([
        DeviceGroup("group-1", "Ground floor", null, "", ["device-1", "device-2"], null),
        DeviceGroup("group-2", "Living room", null, "", ["device-3"], null),
        DeviceGroup("group-3", "All lamps", null, "", [], null),
      ]);
      await pumpGolden(tester, tabScreen(const GroupList()), dark: dark);
      await expectLater(
          find.byType(MaterialApp), matchesGoldenFile("goldens/groups_list_$suffix.png"));
    });

    testWidgets("networks list ($suffix)", (tester) async {
      AppState().networks.addAll([
        Network("network-1", "Ground floor", false, ["device-1-local"], ["device-1"],
            DeviceConnectionStatus.online, "hash-1", "owner-1"),
        Network("network-2", "Garage", false, ["device-2-local"], ["device-2"],
            DeviceConnectionStatus.offline, "hash-2", "owner-1"),
        Network("network-3", "Guest house", false, [], [], DeviceConnectionStatus.unknown,
            "hash-3", "owner-1"),
      ]);
      await pumpGolden(tester, tabScreen(const DeviceListByNetwork()), dark: dark);
      await expectLater(
          find.byType(MaterialApp), matchesGoldenFile("goldens/networks_list_$suffix.png"));
    });

    testWidgets("device classes list ($suffix)", (tester) async {
      final lamp = DeviceClass("class-1", "Lamps", "")..deviceIds.addAll(["device-1", "device-2"]);
      final heating = DeviceClass("class-2", "Heating", "")..deviceIds.add("device-3");
      final sensor = DeviceClass("class-3", "Sensors", "");
      AppState().deviceClasses.addAll({
        lamp.id: lamp,
        heating.id: heating,
        sensor.id: sensor,
      });
      await pumpGolden(tester, tabScreen(const DeviceListByDeviceClass()), dark: dark);
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile("goldens/device_classes_list_$suffix.png"));
    });

    testWidgets("device list ($suffix)", (tester) async {
      final devices = [
        DeviceInstance("device-1", "device-1-local", "Living room lamp", null,
            "device-type-1", false, "owner-1", "Living room lamp", DeviceConnectionStatus.online),
        DeviceInstance("device-2", "device-2-local", "Heat pump", null, "device-type-2",
            false, "owner-1", "Heat pump", DeviceConnectionStatus.online),
        DeviceInstance("device-3", "device-3-local", "Garage door", null, "device-type-3",
            false, "owner-1", "Garage door", DeviceConnectionStatus.offline),
      ];
      AppState().devices.addAll(devices);
      AppState().totalDevices = devices.length;
      await pumpGolden(tester, tabScreen(const DeviceList()), dark: dark);
      await expectLater(
          find.byType(MaterialApp), matchesGoldenFile("goldens/device_list_$suffix.png"));
    });
  }
}
