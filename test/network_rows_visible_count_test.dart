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
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/widgets/tabs/networks/device_networks.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

Map<String, dynamic> networkJson(String id, String name,
        {required List<String> localIds, List<String>? deviceIds}) =>
    {
      "id": id,
      "name": name,
      "hash": "",
      "owner_id": "owner-1",
      "shared": false,
      "device_local_ids": localIds,
      if (deviceIds != null) "device_ids": deviceIds,
      "connection_state": "online",
    };

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  testWidgets(
      "network rows count only the devices their list shows, a network with "
      "only hidden devices still opens, and rows without device_ids fall "
      "back to the local id count", (tester) async {
    await warmUpMgwStorage(tester);
    final backend = FakeBackend();
    backend.serveJson("GET", "/device-repository/device-groups", 200, []);
    backend.serveJson("GET", "/device-repository/device-types", 200, []);
    backend.serveJson("GET", "/device-repository/user-device-types", 200, []);
    backend.serveJson("GET", "/device-repository/extended-hubs", 200, [
      networkJson("net-1", "Mixed",
          localIds: ["a-local", "i-local"],
          deviceIds: ["active-1", "inactive-1"]),
      networkJson("net-2", "Hidden",
          localIds: ["i-local"], deviceIds: ["inactive-1"]),
      networkJson("net-3", "Legacy", localIds: ["x-local", "y-local", "z"]),
    ]);
    backend.serveDevicesPaged([
      deviceJson("active-1", "Active 1"),
      deviceJson("inactive-1", "Inactive 1", inactive: true),
    ]);
    serveGoldenBackend(backend);

    await pumpGolden(
        tester, const Scaffold(body: DeviceListByNetwork()),
        dark: false);
    // What loading a device list does; it teaches the app which devices are
    // inactive. A filter equal to the initial empty one would be skipped.
    unawaited(AppState()
        .searchDevices(DeviceSearchFilter("", networkIds: ["net-1"])));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    unawaited(
        AppState().loadNetworks(tester.element(find.byType(DeviceListByNetwork))));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text("Mixed"), findsOneWidget);
    expect(find.text("1 Device"), findsOneWidget, reason: "mixed network");
    expect(find.text("0 Devices"), findsOneWidget, reason: "hidden only");
    expect(find.text("3 Devices"), findsOneWidget, reason: "no device_ids");

    ListTile rowOf(String name) => tester.widget<ListTile>(find.ancestor(
        of: find.text(name), matching: find.byType(ListTile)));
    expect(rowOf("Hidden").onTap, isNotNull,
        reason: "a network whose devices are all hidden still opens");

    // "Show inactive" on: the row counts every member.
    unawaited(AppState().searchDevices(
        DeviceSearchFilter("", networkIds: ["net-1"], showInactive: true)));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text("2 Devices"), findsOneWidget);
    expect(find.text("1 Device"), findsOneWidget);
  });
}
