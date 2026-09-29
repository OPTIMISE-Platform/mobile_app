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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/widgets/tabs/classes/device_class.dart';
import 'package:mobile_app/widgets/tabs/groups/group_list.dart';
import 'package:mobile_app/widgets/tabs/locations/device_location.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/detail_page.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

// One testWidgets for all screens: a second one in the same process may not
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
      "location, class and group rows and the group header count only the "
      "devices their list shows", (tester) async {
    await warmUpMgwStorage(tester);
    const ids = ["active-1", "active-2", "inactive-1"];
    final backend = FakeBackend();
    backend.serveJson("GET", "/device-repository/device-groups", 200, []);
    backend.serveJson("GET", "/device-repository/extended-hubs", 200, []);
    backend.serveJson("GET", "/device-repository/device-types", 200, []);
    backend.serveJson("GET", "/device-repository/user-device-types", 200, []);
    backend.serveJson("GET", "/device-repository/locations", 200, [
      {
        "id": "location-1",
        "name": "Kitchen",
        "description": "",
        "image": "",
        "device_ids": ids,
        "device_group_ids": [],
      }
    ]);
    backend.serveJson("GET", "/api-aggregator/device-class-uses", 200, {
      "device-classes": [
        {"id": "class-1", "name": "Lamps", "image": ""}
      ],
      "used-devices": {"class-1": ids},
    });
    backend.serveDevicesPaged([
      deviceJson("active-1", "Active 1"),
      deviceJson("active-2", "Active 2"),
      deviceJson("inactive-1", "Inactive 1", inactive: true),
    ]);
    serveGoldenBackend(backend);

    Future<void> pumpScreen(Widget screen) async {
      await pumpGolden(tester, Scaffold(body: screen), dark: false);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    final group = DeviceGroup("group-1", "Ground floor", null, "", ids, null);
    AppState().deviceGroups.add(group);
    // What opening the group does; it also lets the header render, which waits
    // for the list to end.
    unawaited(AppState()
        .searchDevices(DeviceSearchFilter("", deviceGroupIds: [group.id])));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    await pumpScreen(const GroupList());
    expect(find.text("2 Devices"), findsOneWidget, reason: "group row");

    await pumpScreen(const DeviceListByDeviceClass());
    expect(find.text("Lamps"), findsOneWidget);
    expect(find.text("2 Devices"), findsOneWidget, reason: "class row");

    await pumpScreen(const DeviceListByLocation());
    expect(find.text("Kitchen"), findsOneWidget);
    expect(find.text("2 Devices, 0 Groups"), findsOneWidget,
        reason: "location row");

    await pumpScreen(DetailPage(null, group));
    expect(find.text("2 Devices"), findsOneWidget, reason: "group header");

    // "Show inactive" on: the same rows count every member.
    unawaited(AppState().searchDevices(
        DeviceSearchFilter("", deviceGroupIds: [group.id], showInactive: true)));
    await pumpScreen(const GroupList());
    expect(find.text("3 Devices"), findsOneWidget);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  });
}
