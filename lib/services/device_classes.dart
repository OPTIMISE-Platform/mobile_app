/*
 * Copyright 2022 InfAI (CC SES)
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

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile_app/models/device_class.dart';
import 'package:mobile_app/services/api_available.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/account_epoch.dart';
import 'package:mobile_app/shared/dio_factory.dart';
import 'package:mobile_app/shared/dio_status.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/shared/metadata_cache.dart';

class DeviceClassesService {
  static String uri =
      '${Settings.getApiUrl() ?? 'localhost'}/device-repository/v2/device-classes';

  static const _pageSize = 1000;

  /// Every device class of the platform, sorted by name. Which of them the
  /// user has devices of follows from the device types, see
  /// `DeviceMixin.usedDeviceClasses`. [maxAge] and [serveStale] as in
  /// [loadMetadataCached].
  static Future<List<DeviceClass>> getDeviceClasses(
      {Duration maxAge = metadataMaxAge,
      void Function(DateTime storedAt)? serveStale}) async {
    await (_legacyMigration ??= _migrateLegacy());
    return loadMetadataCached(_key, _fetchRaw, DeviceClass.fromJson,
        maxAge: maxAge, serveStale: serveStale);
  }

  static const _key = 'device-classes';

  /// The stored answer of the removed api-aggregator endpoint.
  static const _legacyKey = 'device-class-uses';

  static Future<void>? _legacyMigration;

  @visibleForTesting
  static void resetLegacyMigrationForTest() => _legacyMigration = null;

  /// Without a copy of its own, the classes of the old entry are stored as a
  /// stale one, so local mode keeps its classes and the next pass refetches.
  /// The old entry is deleted only once a copy of the new key exists. Never
  /// throws: an unusable old entry is logged and left alone.
  static Future<void> _migrateLegacy() async {
    try {
      final epoch = AccountEpoch.current;
      final legacy = await MetadataCache.readEntry(_legacyKey);
      if (legacy == null) return;
      if (await MetadataCache.readEntry(_key) == null) {
        final decoded = jsonDecode(utf8.decode(legacy.bytes));
        final classes = (decoded as Map<String, dynamic>)["device-classes"];
        if (classes is! List) return;
        final sorted = _sorted([
          for (final c in classes) DeviceClass.fromJson(c as Map<String, dynamic>).toJson()
        ]);
        await MetadataCache.write(_key, JsonUtf8Encoder().convert(sorted), epoch,
            storedAt: DateTime.fromMillisecondsSinceEpoch(0));
        if (await MetadataCache.readEntry(_key) == null) return;
      }
      await MetadataCache.delete(_legacyKey);
    } catch (e, s) {
      ErrorReporter.log('Could not migrate the stored device classes', e, s);
    }
  }

  static Future<List<dynamic>> _fetchRaw() async {
    final headers = await Auth().getHeaders();
    // Uncached dio — persisted via MetadataCache (Isar) instead of Hive.
    final dio = await DioFactory.create(DioConfig.standard);
    final byId = <String, Map<String, dynamic>>{};
    var fetched = 0;
    while (true) {
      final Response<List<dynamic>?> resp;
      try {
        // Paged by id, which is unique, so no class falls between two pages.
        resp = await dio.get<List<dynamic>?>(uri,
            queryParameters: {
              "limit": "$_pageSize",
              "offset": "$fetched",
              "sort": "id.asc",
            },
            options: Options(headers: headers));
      } on DioException catch (e) {
        checkReadStatus(e, uri);
        rethrow;
      }
      final page = resp.data ?? const [];
      final known = byId.length;
      for (final c in page) {
        final m = c as Map<String, dynamic>;
        byId[m["id"] as String] = m;
      }
      fetched += page.length;
      final total = int.tryParse(resp.headers.value('X-Total-Count') ?? '');
      // The total, when sent, ends the list even if the backend caps the
      // page below [_pageSize]; without it a short page does. A page with
      // nothing new ends it too, so a backend ignoring the offset cannot loop.
      if (byId.length == known ||
          (total != null ? fetched >= total : page.length < _pageSize)) {
        break;
      }
    }
    return _sorted(byId.values.toList());
  }

  /// Stored in display order, which is the order the map keeps them in.
  static List<dynamic> _sorted(List<dynamic> classes) => classes
    ..sort((a, b) {
      final byName = _name(a).compareTo(_name(b));
      return byName != 0
          ? byName
          : (a["id"] as String).compareTo(b["id"] as String);
    });

  static String _name(dynamic c) =>
      ((c as Map<String, dynamic>)["name"] as String? ?? "").toLowerCase();

  static bool isAvailable() => ApiAvailableService().isAvailable(uri);
}
