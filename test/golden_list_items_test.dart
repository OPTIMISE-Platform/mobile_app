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
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/models/location.dart';
import 'package:mobile_app/widgets/shared/slice_position.dart';
import 'package:mobile_app/widgets/tabs/shared/device_list_item.dart';
import 'package:mobile_app/widgets/tabs/shared/group_list_item.dart';

import 'golden_helper.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
  });

  DeviceInstance device(String id, String name, bool? on,
      {String deviceTypeId = "device-type-1",
      DeviceConnectionStatus status = DeviceConnectionStatus.online}) {
    final d = DeviceInstance(
      id,
      "$id-local",
      name,
      null,
      deviceTypeId,
      false,
      "owner-1",
      name,
      status,
    );
    if (on != null) {
      d.states.add(DeviceState(
        on,
        "service-1",
        "service-group-1",
        dotenv.env["FUNCTION_GET_ON_OFF_STATE"]!,
        "aspect-1",
        false,
        null,
        null,
        d.id,
        "path",
        "group",
      ));
      // Without a control the list shows no toggle.
      d.states.add(DeviceState(
        null,
        "service-1",
        "service-group-1",
        dotenv.env["FUNCTION_SET_ON_STATE"]!,
        "aspect-1",
        true,
        null,
        null,
        d.id,
        "path",
        "group",
      ));
      d.states.add(DeviceState(
        null,
        "service-1",
        "service-group-1",
        dotenv.env["FUNCTION_SET_OFF_STATE"]!,
        "aspect-1",
        true,
        null,
        null,
        d.id,
        "path",
        "group",
      ));
    }
    return d;
  }

  Widget listItemScreen(Widget child) => Scaffold(body: Material(child: child));

  for (final dark in [false, true]) {
    final suffix = dark ? "dark" : "light";

    testWidgets("device list item, on ($suffix)", (tester) async {
      // No device type/class registered: exercises the fallback icon,
      // together with the location subtitle.
      AppState()
          .locations
          .add(Location("location-1", "Living room", "", "", ["device-1"], []));

      await pumpGolden(
        tester,
        listItemScreen(DeviceListItem(device("device-1", "Living room lamp", true), null,
            position: SlicePosition.only)),
        dark: dark,
      );
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile("goldens/device_list_item_on_$suffix.png"));
    });

    testWidgets("device list item, off ($suffix)", (tester) async {
      // No device type/class registered and no location: exercises the
      // fallback icon and the plain (no subtitle) row.
      await pumpGolden(
        tester,
        listItemScreen(DeviceListItem(device("device-2", "Heat pump", false), null,
            position: SlicePosition.only)),
        dark: dark,
      );
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile("goldens/device_list_item_off_$suffix.png"));
    });

    testWidgets("device list item, offline ($suffix)", (tester) async {
      // Exercises the "Offline" chip, alone in the subtitle line since the
      // device is in no location.
      await pumpGolden(
        tester,
        listItemScreen(DeviceListItem(
            device("device-3", "Garage door", null,
                status: DeviceConnectionStatus.offline),
            null,
            position: SlicePosition.only)),
        dark: dark,
      );
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile("goldens/device_list_item_offline_$suffix.png"));
    });

    testWidgets("group list item ($suffix)", (tester) async {
      final group = DeviceGroup(
        "group-1",
        "Ground floor",
        null,
        "",
        ["device-1", "device-2"],
        null,
      );
      await pumpGolden(
        tester,
        listItemScreen(GroupListItem(group, null, position: SlicePosition.only)),
        dark: dark,
      );
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile("goldens/group_list_item_$suffix.png"));
    });
  }
}
