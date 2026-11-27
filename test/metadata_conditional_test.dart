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
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:isar_community/isar.dart';
import 'package:mobile_app/models/cached_metadata.dart';
import 'package:mobile_app/models/exception_log_element.dart';
import 'package:mobile_app/services/aspects.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/characteristics.dart';
import 'package:mobile_app/services/concepts.dart';
import 'package:mobile_app/services/device_classes.dart';
import 'package:mobile_app/services/device_types.dart';
import 'package:mobile_app/services/functions.dart';
import 'package:mobile_app/shared/account_epoch.dart';
import 'package:mobile_app/shared/metadata_cache.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';
import 'test_helper.dart';

const _aspectsPath = "/device-repository/aspects";
const _functionsPath = "/device-repository/functions";
const _classesPath = "/device-repository/v2/device-classes";
const _typesPath = "/device-repository/device-types";
const _userTypesPath = "/device-repository/user-device-types";

final _aspects = [
  {"id": "a1", "name": "Air"}
];

void main() {
  late Isar db;
  late FakeBackend backend;

  setUpAll(() async {
    await setUpGoldenEnvironment();
    db = await openTestIsar([CachedMetadataSchema, ExceptionLogElementSchema]);
    Auth().loggedIn = true;
  });

  tearDownAll(() => Auth().loggedIn = false);

  setUp(() async {
    await db.writeTxn(() => db.cachedMetadatas.clear());
    backend = FakeBackend();
    serveGoldenBackend(backend);
    serveDeviceTypes(backend);
  });

  tearDown(resetGoldenBackend);

  Future<bool> until(bool Function() condition) async {
    for (var i = 0; i < 300 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return condition();
  }

  /// The cache write after a fetch is not awaited by the service.
  Future<CachedMetadata> stored(String key,
      [bool Function(CachedMetadata e)? where]) async {
    CachedMetadata? entry;
    await until(() {
      // Isar reads here are async; poll on the last value read.
      db.cachedMetadatas.getByKey(key).then((e) => entry = e);
      final e = entry;
      return e != null && (where == null || where(e));
    });
    final e = await db.cachedMetadatas.getByKey(key);
    expect(e, isNotNull, reason: "nothing stored under $key");
    return e!;
  }

  Future<void> age(String key, Duration by) async {
    final e = (await db.cachedMetadatas.getByKey(key))!;
    e.updatedAt = DateTime.now().subtract(by);
    await db.writeTxn(() => db.cachedMetadatas.putByKey(e));
  }

  String? ifNoneMatch(RequestOptions o) {
    for (final e in o.headers.entries) {
      if (e.key.toLowerCase() == 'if-none-match') return e.value?.toString();
    }
    return null;
  }

  List<RequestOptions> to(String path) =>
      backend.requests.where((r) => r.uri.path == path).toList();

  group("revalidation", () {
    test("a 200 with an ETag is stored with it and the URI it came from, "
        "and a 304 renews the stored copy", () async {
      backend.serveJson("GET", _aspectsPath, 200, _aspects,
          headers: {"ETag": '"v1"'}, notModifiedFor: '"v1"');

      expect((await AspectsService.getAspects()).map((a) => a.id), ["a1"]);
      final first = await stored('aspects', (e) => e.etag != null);
      expect(first.etag, '"v1"');
      expect(first.etagUri, to(_aspectsPath).single.uri.toString());
      expect(ifNoneMatch(to(_aspectsPath).single), isNull);

      await age('aspects', const Duration(hours: 3));
      final aged = (await db.cachedMetadatas.getByKey('aspects'))!;

      final again =
          await AspectsService.getAspects(maxAge: Duration.zero);

      expect(again.map((a) => a.id), ["a1"]);
      expect(ifNoneMatch(to(_aspectsPath).last), '"v1"');
      final after = (await db.cachedMetadatas.getByKey('aspects'))!;
      expect(after.updatedAt.isAfter(aged.updatedAt), isTrue,
          reason: "the 304 renews the time");
      expect(after.bytes, aged.bytes);
      expect(after.etag, '"v1"');
      expect(after.etagUri, first.etagUri);
    });

    test("a weak ETag goes there and back as sent", () async {
      backend.serveJson("GET", _aspectsPath, 200, _aspects,
          headers: {"ETag": 'W/"x"'}, notModifiedFor: 'W/"x"');

      await AspectsService.getAspects();
      expect((await stored('aspects', (e) => e.etag != null)).etag, 'W/"x"');
      await AspectsService.getAspects(maxAge: Duration.zero);

      expect(ifNoneMatch(to(_aspectsPath).last), 'W/"x"');
      expect(to(_aspectsPath), hasLength(2));
    });

    test("a different ETag with 200 replaces bytes and validator", () async {
      backend.serveJson("GET", _aspectsPath, 200, _aspects,
          headers: {"ETag": '"v1"'});
      await AspectsService.getAspects();
      await stored('aspects', (e) => e.etag == '"v1"');

      backend.serveJson("GET", _aspectsPath, 200,
          [
            {"id": "a2", "name": "Water"}
          ],
          headers: {"ETag": '"v2"'}, notModifiedFor: '"v2"');
      final fresh = await AspectsService.getAspects(maxAge: Duration.zero);

      expect(fresh.map((a) => a.id), ["a2"]);
      expect(ifNoneMatch(to(_aspectsPath).last), '"v1"');
      final e = await stored('aspects', (e) => e.etag == '"v2"');
      expect(utf8.decode(e.bytes), contains("a2"));
    });

    test("an answer without ETag leaves no validator, the next request is "
        "unconditional and the entry stays current for seven days", () async {
      backend.serveJson("GET", _aspectsPath, 200, _aspects);
      await AspectsService.getAspects();
      final e = await stored('aspects');
      expect(e.etag, isNull);
      expect(e.etagUri, isNull);

      await AspectsService.getAspects(maxAge: Duration.zero);
      expect(ifNoneMatch(to(_aspectsPath).last), isNull);

      await age('aspects', const Duration(hours: 2));
      DateTime? reported;
      await AspectsService.getAspects(serveStale: (t) => reported = t);
      expect(to(_aspectsPath), hasLength(2), reason: "served from the store");
      expect(MetadataCache.isStale(reported!, metadataMaxAge), isFalse);
    });

    test("an entry with a validator is current for metadataMaxAge, then "
        "fetched conditionally", () async {
      backend.serveJson("GET", _aspectsPath, 200, _aspects,
          headers: {"ETag": '"v1"'}, notModifiedFor: '"v1"');
      await AspectsService.getAspects();
      await stored('aspects', (e) => e.etag != null);

      await age('aspects', const Duration(days: 6));
      DateTime? reported;
      await AspectsService.getAspects(serveStale: (t) => reported = t);
      expect(to(_aspectsPath), hasLength(1), reason: "served from the store");
      expect(MetadataCache.isStale(reported!, metadataMaxAge), isFalse);

      await age('aspects', const Duration(days: 8));
      await AspectsService.getAspects(serveStale: (t) => reported = t);
      expect(to(_aspectsPath), hasLength(1),
          reason: "stale is served, the pass revalidates");
      expect(MetadataCache.isStale(reported!, metadataMaxAge), isTrue);

      await AspectsService.getAspects();
      expect(to(_aspectsPath), hasLength(2));
      expect(ifNoneMatch(to(_aspectsPath).last), '"v1"');
    });

    test("a 304 reports a time at which the set is not yet due", () async {
      backend.serveJson("GET", _aspectsPath, 200, _aspects,
          headers: {"ETag": '"v1"'}, notModifiedFor: '"v1"');
      await AspectsService.getAspects();
      await stored('aspects', (e) => e.etag != null);

      DateTime? reported;
      await AspectsService.getAspects(
          maxAge: Duration.zero, serveStale: (t) => reported = t);

      expect(ifNoneMatch(to(_aspectsPath).last), '"v1"');
      expect(MetadataCache.isStale(reported!, metadataMaxAge), isFalse);
      expect(
          MetadataCache.isStale(
              reported!, metadataMaxAge,
              DateTime.now().add(metadataMaxAge + const Duration(minutes: 1))),
          isTrue);
    });

    test("a list over several pages has no validator and is fetched "
        "unconditionally", () async {
      backend.types[_functionsPath] = [
        for (var i = 0; i < 10000; i++)
          {
            "id": "f$i",
            "name": "F$i",
            "concept_id": "c",
            "display_name": "F$i"
          }
      ];
      backend.typesHeaders[_functionsPath] = {"ETag": '"p"'};

      final all = await FunctionsService.getFunctions();
      expect(all, hasLength(10000));
      expect(to(_functionsPath), hasLength(2));
      final e = await stored('functions');
      expect(e.etag, isNull);
      expect(e.etagUri, isNull);

      await FunctionsService.getFunctions(maxAge: Duration.zero);
      expect(to(_functionsPath).skip(2).map(ifNoneMatch), [null, null]);
    });

    test("device classes over one page keep the sorted, deduplicated list "
        "and a 304 serves it", () async {
      backend.serveJson(
          "GET",
          _classesPath,
          200,
          [
            deviceClassJson("c2", "Zebra"),
            deviceClassJson("c1", "Ant"),
            deviceClassJson("c1", "Ant"),
          ],
          headers: {"ETag": '"k"', "X-Total-Count": "3"},
          notModifiedFor: '"k"');

      expect((await DeviceClassesService.getDeviceClasses()).map((c) => c.id),
          ["c1", "c2"]);
      await stored('device-classes', (e) => e.etag != null);

      final again = await DeviceClassesService.getDeviceClasses(
          maxAge: Duration.zero);

      expect(again.map((c) => c.id), ["c1", "c2"]);
      expect(ifNoneMatch(to(_classesPath).last), '"k"');
    });

    test("device classes over several pages have no validator", () async {
      // Every page is the same 1000 classes, so the second one ends the list.
      backend.serveJson(
          "GET",
          _classesPath,
          200,
          [for (var i = 0; i < 1000; i++) deviceClassJson("c$i", "C$i")],
          headers: {"ETag": '"k"', "X-Total-Count": "1500"});

      await DeviceClassesService.getDeviceClasses();

      expect(to(_classesPath), hasLength(2));
      expect((await stored('device-classes')).etag, isNull);
    });
  });

  group("device types", () {
    test("a validator from the fallback is not sent to /user-device-types, "
        "and a 304 from the fallback keeps the whole-platform flag", () async {
      backend.serveJson("GET", _userTypesPath, 404, null);
      backend.serveJson("GET", _typesPath, 200, [deviceTypeJson("t1")],
          headers: {"ETag": '"t"'}, notModifiedFor: '"t"');

      expect((await DeviceTypesService.getDeviceTypes()).map((t) => t.id),
          ["t1"]);
      expect(DeviceTypesService.userListIsAllTypes, isTrue);
      final e = await stored('user-device-types', (e) => e.etag != null);
      expect(e.etagUri, to(_typesPath).single.uri.toString());

      final again =
          await DeviceTypesService.getDeviceTypes(null, Duration.zero);

      expect(again.map((t) => t.id), ["t1"]);
      expect(ifNoneMatch(to(_userTypesPath).last), isNull);
      expect(ifNoneMatch(to(_typesPath).last), '"t"');
      expect(DeviceTypesService.userListIsAllTypes, isTrue);
    });

    test("a 304 from /user-device-types clears the whole-platform flag",
        () async {
      backend.serveJson("GET", _userTypesPath, 200, [deviceTypeJson("t1")],
          headers: {"ETag": '"u"'}, notModifiedFor: '"u"');
      await DeviceTypesService.getDeviceTypes();
      await stored('user-device-types', (e) => e.etag != null);

      final again =
          await DeviceTypesService.getDeviceTypes(null, Duration.zero);

      expect(again.map((t) => t.id), ["t1"]);
      expect(ifNoneMatch(to(_userTypesPath).last), '"u"');
      expect(DeviceTypesService.userListIsAllTypes, isFalse);
    });
  });

  group("other sets", () {
    Future<void> revalidates(String key, String path,
        List<Map<String, dynamic>> body, Future<List<Object>> Function(Duration) load) async {
      backend.serveJson("GET", path, 200, body,
          headers: {"ETag": '"e"'}, notModifiedFor: '"e"');

      final first = await load(metadataMaxAge);
      final e = await stored(key, (e) => e.etag != null);
      expect(e.etag, '"e"');
      expect(e.etagUri, to(path).single.uri.toString());
      expect(ifNoneMatch(to(path).single), isNull);

      final again = await load(Duration.zero);

      expect(ifNoneMatch(to(path).last), '"e"');
      expect(to(path), hasLength(2));
      expect(again, hasLength(first.length));
      expect(again, isNotEmpty);
    }

    test("concepts store the validator and a 304 serves the stored data",
        () => revalidates('concepts',
            "/device-repository/v2/concepts-with-characteristics", [
          {
            "id": "c1",
            "name": "Temperature",
            "base_characteristic_id": "ch1",
            "characteristics": <dynamic>[]
          }
        ], (maxAge) => ConceptsService.getConcepts(maxAge: maxAge)));

    test("characteristics store the validator and a 304 serves the stored "
        "data", () => revalidates('characteristics',
            "/device-repository/characteristics", [
          {
            "id": "ch1",
            "name": "Celsius",
            "type": "https://schema.org/Float",
            "display_unit": "C"
          }
        ], (maxAge) => CharacteristicsService.getCharacteristics(maxAge: maxAge)));

    test("a device type list over several pages has no validator and is "
        "fetched unconditionally", () async {
      backend.types[_userTypesPath] = [
        for (var i = 0; i < 10000; i++) deviceTypeJson("t$i")
      ];
      backend.typesHeaders[_userTypesPath] = {"ETag": '"p"'};

      expect(await DeviceTypesService.getDeviceTypes(), hasLength(10000));
      expect(to(_userTypesPath), hasLength(2));
      final e = await stored('user-device-types');
      expect(e.etag, isNull);
      expect(e.etagUri, isNull);

      await DeviceTypesService.getDeviceTypes(null, Duration.zero);
      expect(to(_userTypesPath).skip(2).map(ifNoneMatch), [null, null]);
    });
  });

  group("guards", () {
    test("an account change between request and 304 leaves the stored time "
        "alone", () async {
      backend.serveJson("GET", _aspectsPath, 200, _aspects,
          headers: {"ETag": '"v1"'}, notModifiedFor: '"v1"');
      await AspectsService.getAspects();
      await stored('aspects', (e) => e.etag != null);
      await age('aspects', const Duration(hours: 3));
      final before = (await db.cachedMetadatas.getByKey('aspects'))!;

      final gate = Completer<void>();
      backend.holds["GET $_aspectsPath"] = gate;
      final load = AspectsService.getAspects(maxAge: Duration.zero);
      expect(await until(() => to(_aspectsPath).length == 2), isTrue);
      AccountEpoch.advance();
      gate.complete();
      await load;
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final after = (await db.cachedMetadatas.getByKey('aspects'))!;
      expect(after.updatedAt.isAtSameMomentAs(before.updatedAt), isTrue);
    });

    test("a corrupt entry with a validator is fetched without it", () async {
      // The validator is the real one, for the real request URI, and the
      // backend would answer it with 304: only dropping it avoids the 304.
      backend.serveJson("GET", _aspectsPath, 200, _aspects,
          headers: {"ETag": '"v1"'}, notModifiedFor: '"v1"');
      await AspectsService.getAspects();
      final good = await stored('aspects', (e) => e.etag != null);
      await db.writeTxn(() => db.cachedMetadatas.putByKey(CachedMetadata()
        ..key = 'aspects'
        ..bytes = utf8.encode("not json")
        ..updatedAt = DateTime.now().subtract(const Duration(minutes: 5))
        ..etag = good.etag
        ..etagUri = good.etagUri));
      backend.serveJson("GET", _aspectsPath, 200, _aspects,
          headers: {"ETag": '"v2"'}, notModifiedFor: '"v1"');

      final result = await AspectsService.getAspects();

      expect(result.map((a) => a.id), ["a1"]);
      expect(to(_aspectsPath), hasLength(2), reason: "one request, no retry");
      expect(ifNoneMatch(to(_aspectsPath).last), isNull);
      final e = await stored('aspects', (e) => e.etag == '"v2"');
      expect(utf8.decode(e.bytes), contains("a1"));
    });

    test("a 304 over bytes that cannot be used is followed by an "
        "unconditional request", () async {
      backend.serveJson("GET", _aspectsPath, 200, _aspects,
          headers: {"ETag": '"v1"'}, notModifiedFor: '"v1"');
      await AspectsService.getAspects();
      final good = await stored('aspects', (e) => e.etag != null);
      await db.writeTxn(() => db.cachedMetadatas.putByKey(CachedMetadata()
        ..key = 'aspects'
        ..bytes = utf8.encode("not json")
        ..updatedAt = good.updatedAt
        ..etag = good.etag
        ..etagUri = good.etagUri));

      final result = await AspectsService.getAspects(maxAge: Duration.zero);

      expect(result.map((a) => a.id), ["a1"]);
      expect(to(_aspectsPath).map(ifNoneMatch).skip(1), ['"v1"', null]);
    });
  });
}
