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

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:mobile_app/models/cached_metadata.dart';
import 'package:mobile_app/models/exception_log_element.dart';
import 'package:mobile_app/services/device_classes.dart';
import 'package:mobile_app/shared/metadata_cache.dart';

import 'test_helper.dart';

Future<void> _put(Isar db, String key, DateTime updatedAt, Object body) =>
    db.writeTxn(() => db.cachedMetadatas.putByKey(CachedMetadata()
      ..key = key
      ..bytes = utf8.encode(jsonEncode(body))
      ..updatedAt = updatedAt));

void main() {
  late Isar db;
  var fetches = 0;
  var fetchFails = false;

  Future<List<dynamic>> fetch() async {
    fetches++;
    if (fetchFails) throw Exception("offline");
    return [
      {"v": "fetched"}
    ];
  }

  Future<List<String>> load(
          {Duration maxAge = metadataMaxAge,
          void Function(DateTime storedAt)? serveStale}) =>
      loadMetadataCached('k', fetch, (j) => j["v"] as String,
          maxAge: maxAge, serveStale: serveStale);

  setUpAll(() async {
    setUpTestEnvironment();
    db = await openTestIsar([CachedMetadataSchema, ExceptionLogElementSchema]);
  });

  setUp(() async {
    await db.writeTxn(() => db.cachedMetadatas.clear());
    fetches = 0;
    fetchFails = false;
  });

  test("an entry older than maxAge is served when stale is allowed, and "
      "reported with its stored time", () async {
    final storedAt = DateTime.now().subtract(const Duration(days: 8));
    await _put(db, 'k', storedAt, [
      {"v": "stored"}
    ]);

    DateTime? reported;
    final result = await load(serveStale: (t) => reported = t);

    expect(result, ["stored"]);
    expect(fetches, 0);
    expect(reported!.isAtSameMomentAs(storedAt), isTrue,
        reason: "reported $reported, stored $storedAt");
    expect(MetadataCache.isStale(reported!, metadataMaxAge), isTrue);
  });

  test("without stale allowed the same entry is fetched", () async {
    await _put(db, 'k', DateTime.now().subtract(const Duration(days: 8)), [
      {"v": "stored"}
    ]);

    expect(await load(), ["fetched"]);
    expect(fetches, 1);
  });

  test("an entry younger than maxAge is served and reported current",
      () async {
    await _put(db, 'k', DateTime.now().subtract(const Duration(days: 1)), [
      {"v": "stored"}
    ]);

    DateTime? reported;
    expect(await load(serveStale: (t) => reported = t), ["stored"]);
    expect(fetches, 0);
    expect(MetadataCache.isStale(reported!, metadataMaxAge), isFalse);
  });

  test("an entry dated in the future is served and reported stale", () async {
    await _put(db, 'k', DateTime.now().add(const Duration(days: 1)), [
      {"v": "stored"}
    ]);

    DateTime? reported;
    expect(await load(serveStale: (t) => reported = t), ["stored"]);
    expect(MetadataCache.isStale(reported!, metadataMaxAge), isTrue);
  });

  test("with nothing stored the fetch blocks and is reported as current",
      () async {
    DateTime? reported;
    expect(await load(serveStale: (t) => reported = t), ["fetched"]);
    expect(fetches, 1);
    expect(MetadataCache.isStale(reported!, metadataMaxAge), isFalse);
  });

  test("Duration.zero fetches even over a current entry with stale allowed, "
      "and keeps the stored copy when the fetch throws", () async {
    final storedAt = DateTime.now().subtract(const Duration(hours: 1));
    await _put(db, 'k', storedAt, [
      {"v": "stored"}
    ]);
    fetchFails = true;

    DateTime? reported;
    await expectLater(
        load(maxAge: Duration.zero, serveStale: (t) => reported = t),
        throwsException);
    expect(fetches, 1);
    expect(reported, isNull, reason: "nothing was served");

    final entry = await db.cachedMetadatas.getByKey('k');
    expect(entry!.updatedAt.isAtSameMomentAs(storedAt), isTrue);
    expect(await load(), ["stored"], reason: "the next start still has it");
    expect(fetches, 1);
  });

  group("the stored api-aggregator answer", () {
    setUp(DeviceClassesService.resetLegacyMigrationForTest);

    test("serves its classes as a stale copy when nothing newer is stored, "
        "and is deleted once that copy is", () async {
      await _put(db, 'device-class-uses', DateTime.now(), {
        "device-classes": [
          {"id": "c2", "name": "Sensors", "image": ""},
          {"id": "c1", "name": "Lamps", "image": ""},
        ],
        "used-devices": {},
      });

      DateTime? reported;
      // Nothing answers a fetch here, as in local mode.
      final classes = await DeviceClassesService.getDeviceClasses(
          serveStale: (t) => reported = t);

      expect(classes.map((c) => c.id), ["c1", "c2"]);
      expect(MetadataCache.isStale(reported!, metadataMaxAge), isTrue);
      expect(await db.cachedMetadatas.getByKey('device-class-uses'), isNull);
      expect(await db.cachedMetadatas.getByKey('device-classes'), isNotNull);
    });

    test("is deleted when a copy of the new key exists", () async {
      await _put(db, 'device-class-uses', DateTime.now(), {"device-classes": []});
      await _put(db, 'device-classes', DateTime.now(), [
        {"id": "c1", "name": "Lamps", "image": ""}
      ]);

      final classes = await DeviceClassesService.getDeviceClasses();

      expect(classes.map((c) => c.id), ["c1"]);
      expect(await db.cachedMetadatas.getByKey('device-class-uses'), isNull);
    });

    test("with a malformed class is left alone, and later loads still work",
        () async {
      await _put(db, 'device-class-uses', DateTime.now(), {
        "device-classes": [
          42,
          {"id": "c1", "name": "Lamps", "image": ""},
        ],
      });

      await expectLater(DeviceClassesService.getDeviceClasses(),
          throwsA(anything),
          reason: "nothing usable is stored, and the fetch fails here");
      expect(await db.cachedMetadatas.getByKey('device-class-uses'), isNotNull);
      expect(await db.cachedMetadatas.getByKey('device-classes'), isNull);

      await _put(db, 'device-classes', DateTime.now(), [
        {"id": "c1", "name": "Lamps", "image": ""}
      ]);
      final classes = await DeviceClassesService.getDeviceClasses();
      expect(classes.map((c) => c.id), ["c1"]);
    });

    test("is kept when it holds no classes to migrate", () async {
      await _put(db, 'device-class-uses', DateTime.now(), {"other": 1});

      await expectLater(
          DeviceClassesService.getDeviceClasses(maxAge: metadataMaxAge),
          throwsA(anything),
          reason: "nothing stored, and the fetch fails here");
      expect(await db.cachedMetadatas.getByKey('device-class-uses'), isNotNull);
    });
  });

  test("the stored device classes are served whatever their age", () async {
    final storedAt = DateTime.now().subtract(const Duration(days: 30));
    await _put(db, 'device-classes', storedAt, [
      {"id": "c1", "name": "Lamps", "image": ""}
    ]);

    DateTime? reported;
    final classes = await DeviceClassesService.getDeviceClasses(
        serveStale: (t) => reported = t);

    expect(classes.map((c) => c.id), ["c1"]);
    expect(reported!.isAtSameMomentAs(storedAt), isTrue);
  });
}
