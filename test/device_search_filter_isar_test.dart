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


@Tags(['isar'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/models/network.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';
import 'test_helper.dart';

void main() {
  late Isar db;

  setUpAll(() async {
    await setUpGoldenEnvironment();
    db = await openTestIsar([DeviceInstanceSchema]);
    await db.writeTxn(() => db.deviceInstances.putAll([
          for (final (id, type) in [
            ("lamp-1", "lamp-a"),
            ("lamp-2", "lamp-b"),
            ("heater-1", "heater"),
            ("other-1", "other"),
          ])
            DeviceInstance.fromJson(deviceJson(id, id, deviceTypeId: type)),
        ]));
  });

  setUp(() {
    AppState().deviceTypes.addAll({
      "lamp-a": DeviceType("lamp-a", "", "", "lamp", [], null),
      "lamp-b": DeviceType("lamp-b", "", "", "lamp", [], null),
      "heater": DeviceType("heater", "", "", "heating", [], null),
    });
  });

  tearDown(resetAppStateForGolden);

  Future<Set<String>> ids(DeviceSearchFilter f) async =>
      (await f.isarQuery(50, 0, db.deviceInstances).build().findAll())
          .map((d) => d.id)
          .toSet();

  test("a class filter matches the devices of its device types", () async {
    expect(await ids(DeviceSearchFilter("", deviceClassIds: ["lamp"])),
        {"lamp-1", "lamp-2"});
    expect(
        await ids(DeviceSearchFilter("", deviceClassIds: ["lamp", "heating"])),
        {"lamp-1", "lamp-2", "heater-1"});
  });

  test("a class without loaded types matches nothing", () async {
    expect(await ids(DeviceSearchFilter("", deviceClassIds: ["sensors"])),
        isEmpty);
  });

  test("a class filter narrows the other fields further", () async {
    expect(
        await ids(DeviceSearchFilter("",
            deviceClassIds: ["lamp"], deviceIds: ["lamp-1", "heater-1"])),
        {"lamp-1"});
  });

  test("an empty id list matches nothing", () async {
    AppState()
        .deviceGroups
        .add(DeviceGroup("empty", "Empty", null, "", [], null));

    expect(await ids(DeviceSearchFilter("", deviceGroupIds: ["empty"])),
        isEmpty);
    expect(await ids(DeviceSearchFilter("", deviceIds: [])), isEmpty);
  });

  test("a network without local ids matches nothing", () async {
    AppState().networks.add(Network("net", "Garage", false, null, null,
        DeviceConnectionStatus.unknown, "hash", "owner-1"));

    expect(await ids(DeviceSearchFilter("", networkIds: ["net"])), isEmpty);
  });
}
