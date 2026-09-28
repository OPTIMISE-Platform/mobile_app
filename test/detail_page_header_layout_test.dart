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
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/location.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/detail_page.dart';

import 'golden_helper.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
  });

  DeviceInstance device(String id, String name, DeviceConnectionStatus status) =>
      DeviceInstance(id, "$id-local", name, null, "device-type-1", false, "owner-1", name, status);

  Future<void> pumpHeader(WidgetTester tester, Widget page,
      {required double width, required double scale}) {
    return pumpGolden(
      tester,
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: page,
        ),
      ),
      dark: false,
      size: Size(width, 700),
    );
  }

  /// No FlutterError from the pump, and the header's title and subtitle rows
  /// leave disjoint rects - the bug this guards against had the group header
  /// render both on top of each other (see detail_page.dart's header).
  Future<void> expectHeaderLaidOutCleanly(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    final title = tester.getRect(find.byKey(const Key('detailPageHeaderTitle')));
    final subtitle = tester.getRect(find.byKey(const Key('detailPageHeaderSubtitle')));
    expect(title.overlaps(subtitle), isFalse,
        reason: "title $title overlaps subtitle $subtitle");
  }

  for (final width in [320.0, 360.0, 412.0]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets(
          "device detail header at ${width}dp, scale $scale: title/subtitle do not overlap",
          (tester) async {
        final d = device("device-1",
            "Kitchen ceiling light strip with dimmer and colour control",
            DeviceConnectionStatus.offline);
        AppState().devices.add(d);
        AppState().locations.addAll([
          Location("location-1", "Kitchen", "", "", [d.id], []),
          Location("location-2", "Ground floor extension wing", "", "", [d.id], []),
        ]);

        await pumpHeader(tester, DetailPage(d, null), width: width, scale: scale);

        await expectHeaderLaidOutCleanly(tester);
      });

      testWidgets(
          "group detail header at ${width}dp, scale $scale: title/subtitle do not overlap",
          (tester) async {
        final devices = [
          device("device-1", "Living room lamp", DeviceConnectionStatus.online),
          device("device-2", "Heat pump", DeviceConnectionStatus.online),
        ];
        AppState().devices.addAll(devices);
        final group = DeviceGroup(
            "group-1",
            "Ground floor lamps and heating with a very long descriptive name",
            null,
            "",
            devices.map((d) => d.id).toList(),
            null);
        AppState().deviceGroups.add(group);

        await pumpHeader(tester, DetailPage(null, group), width: width, scale: scale);

        await expectHeaderLaidOutCleanly(tester);
      });
    }
  }
}
