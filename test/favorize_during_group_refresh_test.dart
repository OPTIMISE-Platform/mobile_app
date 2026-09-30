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

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/isar.dart';
import 'package:mobile_app/widgets/shared/favorize_button.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';
import 'test_helper.dart';

const _list = "/device-repository/device-groups";
const _detail = "/device-repository/device-groups/group-1";
const _image = "/g.svg";

Map<String, dynamic> _groupJson() => {
      "id": "group-1",
      "name": "Ground floor",
      "image": "https://img.test$_image",
      "criteria": <Map<String, dynamic>>[],
      "device_ids": <String>[],
      "attributes": null,
    };

void main() {
  late Isar db;

  setUpAll(() async {
    db = await openTestIsar([DeviceGroupSchema]);
    await setUpGoldenEnvironment();
    await Settings.setAccount("test-account");
  });

  tearDown(resetGoldenBackend);

  test("a favorite tapped while the refresh loads images survives the refresh",
      () async {
    final backend = FakeBackend();
    backend.serveJson("GET", _list, 200, [_groupJson()]);
    backend.serveJson("GET", _detail, 200, _groupJson());
    backend.serveJson("GET", _image, 404, null);
    final imageHold = Completer<void>();
    backend.holds["GET $_image"] = imageHold;
    serveGoldenBackend(backend);

    final refresh = CacheHelper.refreshDeviceGroupsNow();
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!backend.requests.any((r) => r.uri.path == _image)) {
      if (DateTime.now().isAfter(deadline)) fail("the refresh never loaded the image");
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    // The rows are stored with their mirror by now; the user taps the star
    // while the image is still loading.
    await FavorizeButton(null, DeviceGroup.fromJson(_groupJson())).click();
    imageHold.complete();
    expect(await refresh, isTrue);

    expect(Settings.getFavoriteGroupIds(), contains("group-1"));
    final row = await db.deviceGroups.get(fastHash("group-1"));
    expect(row!.favorite, isTrue, reason: "the refresh's rows carry the tap");
  });
}
