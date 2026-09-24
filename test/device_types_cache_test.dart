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
import 'package:mobile_app/models/cached_metadata.dart';
import 'package:mobile_app/models/exception_log_element.dart';
import 'package:mobile_app/services/device_types.dart';
import 'package:mobile_app/shared/metadata_cache.dart';

import 'fake_backend.dart';
import 'test_helper.dart';

/// The cache write after a fetch is not awaited by the service.
Future<CachedMetadata?> _entry(Isar db, String key) async {
  for (var i = 0; i < 50; i++) {
    final e = await db.cachedMetadatas.getByKey(key);
    if (e != null) return e;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  return null;
}

Future<void> _put(Isar db, String key, DateTime updatedAt) =>
    db.writeTxn(() => db.cachedMetadatas.putByKey(CachedMetadata()
      ..key = key
      ..bytes = '[]'.codeUnits
      ..updatedAt = updatedAt));

void main() {
  late Isar db;
  late FakeBackend backend;

  setUpAll(() async {
    db = await openTestIsar([CachedMetadataSchema, ExceptionLogElementSchema]);
  });

  setUp(() async {
    await db.writeTxn(() => db.cachedMetadatas.clear());
    backend = FakeBackend();
    serveDeviceTypes(backend);
  });

  // First in the file: the service drops the old entry once per process.
  test("the first load removes the old full-list entry", () async {
    await _put(db, 'device-types', DateTime.now());
    backend.types["/device-repository/user-device-types"] = [deviceTypeJson("a")];

    await DeviceTypesService.getDeviceTypes();
    await _entry(db, 'user-device-types');

    expect(await db.cachedMetadatas.getByKey('device-types'), isNull);
  });

  test("the user list is cached under its own key and served from there",
      () async {
    backend.types["/device-repository/user-device-types"] = [deviceTypeJson("a")];

    await DeviceTypesService.getDeviceTypes();
    expect(await _entry(db, 'user-device-types'), isNotNull);
    final second = await DeviceTypesService.getDeviceTypes();

    expect(second.map((t) => t.id), ["a"]);
    expect(backend.requests, hasLength(1));
  });

  test("an entry dated in the future counts as stale", () async {
    await _put(db, 'k', DateTime.now().add(const Duration(days: 1)));

    expect(await MetadataCache.read('k', const Duration(days: 7)), isNull);
  });
}
