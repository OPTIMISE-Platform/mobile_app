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
import 'package:mobile_app/models/device_class.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/models/function.dart';
import 'package:mobile_app/models/location.dart';
import "package:mobile_app/models/notification.dart" as app;
import 'package:mobile_app/widgets/notifications/notification_list.dart';
import 'package:mobile_app/widgets/tabs/locations/location_edit_devices.dart';
import 'package:mobile_app/widgets/tabs/locations/location_edit_groups.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/detail_page.dart';

import 'golden_helper.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
    resetGoldenBackend();
    // Not covered by resetAppStateForGolden (that's NotificationMixin, not
    // Device/Network/DataMixin) - left alone, the notification list test's
    // dark run would append onto the light run's entries.
    AppState().notifications.clear();
  });

  DeviceInstance device(String id, String name, DeviceConnectionStatus status) =>
      DeviceInstance(id, "$id-local", name, null, "device-type-1", false, "owner-1", name, status);

  for (final dark in [false, true]) {
    final suffix = dark ? "dark" : "light";

    // LocationEditGroups: only reads AppState().locations/deviceGroups, no
    // backend call on this path.
    testWidgets("location edit groups ($suffix)", (tester) async {
      AppState().locations.add(Location("location-1", "Ground floor", "", "", [], ["group-1"]));
      AppState().deviceGroups.addAll([
        DeviceGroup("group-1", "Ground floor lamps", null, "", ["device-1", "device-2"], null),
        DeviceGroup("group-2", "Living room", null, "", ["device-3"], null),
      ]);
      await pumpGolden(tester, LocationEditGroups(0), dark: dark);
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile("goldens/location_edit_groups_$suffix.png"));
    });

    // LocationEditDevices: totalDevices pre-filled and the initial filter
    // matches AppState's reset one, so the post-frame searchDevices is a
    // no-op and nothing is fetched.
    testWidgets("location edit devices ($suffix)", (tester) async {
      AppState().locations.add(Location("location-1", "Ground floor", "", "", ["device-1"], []));
      final devices = [
        device("device-1", "Living room lamp", DeviceConnectionStatus.online),
        device("device-2", "Heat pump", DeviceConnectionStatus.online),
      ];
      AppState().devices.addAll(devices);
      AppState().totalDevices = devices.length;
      await pumpGolden(tester, LocationEditDevices(0), dark: dark);
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile("goldens/location_edit_devices_$suffix.png"));
    });

    // NotificationList: uses local time -> toDisplayTime, no backend call.
    testWidgets("notification list ($suffix)", (tester) async {
      AppState().notifications.addAll([
        app.Notification("2026-01-01T10:00:00.000Z", "Backend is unreachable",
            "user-1", "notification-1", false, "Connection lost"),
        app.Notification("2026-01-02T08:30:00.000Z", "Firmware 2.3 available",
            "user-1", "notification-2", true, "Update ready"),
      ]);
      await pumpGolden(tester, const NotificationList(), dark: dark);
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile("goldens/notification_list_$suffix.png"));
    });

    // DetailPage for an offline device: loadStates short-circuits offline
    // devices with a callback(null), so _refresh's post-frame call never
    // touches the backend.
    testWidgets("detail page, offline device ($suffix)", (tester) async {
      AppState().platformFunctions[dotenv.env["FUNCTION_GET_ON_OFF_STATE"]!] =
          PlatformFunction(dotenv.env["FUNCTION_GET_ON_OFF_STATE"]!, "on_off_state", "concept-1", "Power");
      final lamp = DeviceClass("class-1", "Lamps", "");
      AppState().deviceClasses[lamp.id] = lamp;
      AppState().deviceTypes["device-type-1"] =
          DeviceType("device-type-1", "Smart Lamp", "", lamp.id, [], null);
      final d = device("device-1", "Living room lamp", DeviceConnectionStatus.offline);
      d.states.add(DeviceState(true, "service-1", "service-group-1",
          dotenv.env["FUNCTION_GET_ON_OFF_STATE"]!, "aspect-1", false, null, null, d.id, "path", "group"));
      AppState().devices.add(d);
      await pumpGolden(tester, DetailPage(d, null), dark: dark);
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile("goldens/detail_page_offline_device_$suffix.png"));
    });

    // DetailPage for a group whose devices are all already in
    // AppState().devices, so build() never calls loadDevices().
    testWidgets("detail page, group ($suffix)", (tester) async {
      final devices = [
        device("device-1", "Living room lamp", DeviceConnectionStatus.online),
        device("device-2", "Heat pump", DeviceConnectionStatus.online),
      ];
      AppState().devices.addAll(devices);
      final group = DeviceGroup("group-1", "Ground floor", null, "",
          devices.map((d) => d.id).toList(), null);
      AppState().deviceGroups.add(group);
      await pumpGolden(tester, DetailPage(null, group), dark: dark);
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile("goldens/detail_page_group_$suffix.png"));
    });
  }
}
