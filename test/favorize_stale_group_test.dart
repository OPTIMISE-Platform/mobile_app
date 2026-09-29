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
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/isar.dart';
import 'package:mobile_app/widgets/shared/favorize_button.dart';

import 'golden_helper.dart';
import 'test_helper.dart';

Map<String, dynamic> _groupJson(List<Map<String, dynamic>> criteria) => {
      "id": "group-1",
      "name": "Ground floor",
      "image": "",
      "criteria": criteria,
      "device_ids": <String>[],
      "attributes": null,
    };

void main() {
  late Isar db;

  setUpAll(() async {
    // Before the test binding, which answers every HTTP request with 400 and
    // so would block the first download of the Isar core binary.
    db = await openTestIsar([DeviceGroupSchema]);
    await setUpGoldenEnvironment();
    await Settings.setAccount("test-account");
  });

  test("favoriting a group held from a stale cache updates only the favorite of its row", () async {
    final fresh = DeviceGroup.fromJson(_groupJson([
      {"aspect_id": "a", "aspect_ids": ["a", "b"], "device_class_id": "c", "function_id": "f", "interaction": "request"},
    ]));
    await db.writeTxn(() => db.deviceGroups.put(fresh));
    final stale = DeviceGroup.fromJson(_groupJson([
      {"aspect_id": "a", "device_class_id": "c", "function_id": "f", "interaction": "request"},
    ]))
      ..criteriaMayPredateAspectLists = true;

    await FavorizeButton(null, stale).click();

    final row = await db.deviceGroups.get(fastHash("group-1"));
    expect(stale.favorite, isTrue);
    expect(row!.favorite, isTrue);
    expect(row.criteria!.single.aspect_ids, ["a", "b"], reason: "the fresh criteria of the row survive");
  });
}
