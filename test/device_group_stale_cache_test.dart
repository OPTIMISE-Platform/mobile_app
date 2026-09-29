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

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/services/device_groups.dart';
import 'package:mobile_app/services/settings.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

const _stale = [
  {"aspect_id": "a", "device_class_id": "c", "function_id": "f", "interaction": "request"},
];
const _fresh = [
  {"aspect_id": "a", "aspect_ids": ["a"], "device_class_id": "c", "function_id": "f", "interaction": "request"},
  {"aspect_id": "a", "aspect_ids": ["a", "b"], "device_class_id": "c", "function_id": "f", "interaction": "request"},
];

Map<String, dynamic> _groupJson(String name, List<Map<String, dynamic>> criteria) => {
      "id": "group-1",
      "name": name,
      "image": "",
      "criteria": criteria,
      "device_ids": ["device-1"],
      "attributes": null,
    };

DeviceGroup _cachedGroup({required bool stale}) =>
    DeviceGroup.fromJson(_groupJson("Old name", _stale))..criteriaMayPredateAspectLists = stale;

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(resetGoldenBackend);

  // One test for the whole sequence: Dio instances are memoized per process,
  // see docs/testing.md.
  test("stale group rows are never saved back, and the cache is refetched once", () async {
    final backend = FakeBackend();
    serveGoldenBackend(backend);
    const groupPath = "/device-repository/device-groups/group-1";
    const putPath = "/device-manager/device-groups/group-1";
    backend.serveJson("PUT", putPath, 200, _groupJson("New name", _fresh));
    Map<String, dynamic> lastPut() =>
        jsonDecode(backend.requests.lastWhere((r) => r.method == "PUT").data as String) as Map<String, dynamic>;
    int count(String method, String path) =>
        backend.requests.where((r) => r.method == method && r.uri.path == path).length;

    // A row from a possibly stale cache is saved on a fresh copy.
    backend.serveJson("GET", groupPath, 200, _groupJson("Old name", _fresh));
    final stale = _cachedGroup(stale: true);
    await DeviceGroupsService.saveDeviceGroup(stale, (g) => g.name = "New name");
    expect(count("GET", groupPath), 1);
    expect(lastPut()["criteria"], _fresh);
    expect(lastPut()["name"], "New name");
    expect(stale.name, "New name", reason: "the caller's object shows the change as before");

    // A row known to be current is saved as it is, without a fetch.
    await DeviceGroupsService.saveDeviceGroup(_cachedGroup(stale: false), (g) => g.name = "Other name");
    expect(count("GET", groupPath), 1);
    expect(lastPut()["criteria"], _stale);
    expect(lastPut()["name"], "Other name");

    // Without a fresh copy the save fails rather than sending stale criteria.
    backend.serveJson("GET", groupPath, 500, "boom");
    final putsBefore = count("PUT", putPath);
    await expectLater(
        DeviceGroupsService.saveDeviceGroup(_cachedGroup(stale: true), (g) => g.name = "Lost name"), throwsA(anything));
    expect(count("PUT", putPath), putsBefore);

    // The daily refresh counts rows from before aspect lists as never refreshed,
    // until one full refresh has succeeded.
    await Settings.setCacheUpdated("deviceGroups");
    expect(Settings.getDeviceGroupsCachedWithAspectLists(), isFalse);
    expect(CacheHelper.deviceGroupsRefreshedAt(), isNull);

    backend.serveJson("GET", "/device-repository/device-groups", 500, "boom");
    expect(await CacheHelper.refreshDeviceGroupsNow(), isFalse);
    expect(CacheHelper.deviceGroupsRefreshedAt(), isNull, reason: "a failed refresh is retried at the next start");

    backend.serveJson("GET", "/device-repository/device-groups", 200, []);
    expect(await CacheHelper.refreshDeviceGroupsNow(), isTrue);
    expect(Settings.getDeviceGroupsCachedWithAspectLists(), isTrue);
    expect(CacheHelper.deviceGroupsRefreshedAt(), isNotNull, reason: "later starts wait for the day as before");
  });
}
