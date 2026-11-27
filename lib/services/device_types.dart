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


import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:mobile_app/exceptions/unexpected_status_code_exception.dart';
import 'package:mobile_app/shared/account_epoch.dart';
import 'package:mobile_app/shared/conditional_get.dart';
import 'package:mobile_app/shared/dio_status.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/shared/chunked_parse.dart';
import 'package:mobile_app/shared/metadata_cache.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/dio_factory.dart';

import 'package:mobile_app/services/api_available.dart';
import 'package:mobile_app/services/auth.dart';

class DeviceTypesService {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  static String uri = '${Settings.getApiUrl() ?? 'localhost'}/device-repository/device-types';

  static Future<DeviceType?> getDeviceType(String id) async {
    String url = '$uri/$id';


    final headers = await Auth().getHeaders();
    final dio = await DioFactory.create(DioConfig.cached7);
    final Response<Map<String, dynamic>> resp;
    try {
      resp = await dio.get<Map<String, dynamic>>(url, options: Options(headers: headers));
    } on DioException catch (e) {
      checkReadStatus(e, url);
      rethrow;
    }
    if (resp.statusCode == 304) {
      _logger.d("Using cached device type");
    }

    if (resp.data == null || (resp.data is String && (resp.data as String) == "null")) {
      return null;
    }

    return DeviceType.fromJson(resp.data!);
  }


  static String userUri = '${Settings.getApiUrl() ?? 'localhost'}/device-repository/user-device-types';

  static bool _legacyCacheDropped = false;

  /// Plain (uncached) dio — metadata is persisted via MetadataCache instead of
  /// the Hive HTTP cache, whose per-read CRC32 blocked the UI isolate.
  /// Replaceable because the real one's interceptors reach into AppState.
  @visibleForTesting
  static Future<Dio> Function() listDio = () => DioFactory.create(DioConfig.standard);

  @visibleForTesting
  static Future<Map<String, String>> Function() listHeaders = () => Auth().getHeaders();

  /// Without [ids], the device types of the devices the user can see, own or
  /// shared, not every type on the platform. [maxAge] and [serveStale] apply
  /// to that list only, see [loadMetadataCached].
  static Future<List<DeviceType>> getDeviceTypes([List<String>? ids,
      Duration maxAge = metadataMaxAge,
      void Function(DateTime storedAt)? serveStale]) async {
    if (ids != null && ids.isNotEmpty) {
      // Specific ids are fetched fresh and never stored as the full-list cache.
      return parseListChunked(await _fetchRaw(uri, ids), DeviceType.fromJson);
    }
    if (!_legacyCacheDropped) {
      // The full platform list cached under the old key is megabytes that
      // nothing reads any more.
      _legacyCacheDropped = true;
      unawaited(MetadataCache.delete('device-types'));
    }
    final epoch = AccountEpoch.current;
    final storedAll = await _readStoredAllTypes();
    bool? fetchedAll;
    final types = await loadMetadataCached('user-device-types',
        (validator) async {
      final fetched = await _fetchUserTypesRaw(validator);
      fetchedAll = fetched.all;
      return fetched.fetch;
    }, DeviceType.fromJson, maxAge: maxAge,
        serveStale: serveStale == null
            ? null
            // A stored list without the flag may be the platform list a
            // version before the flag stored: reported stale, so the first
            // pass refetches it.
            : (storedAt) => serveStale(fetchedAll == null && storedAll == null
                ? DateTime.fromMillisecondsSinceEpoch(0)
                : storedAt));
    final all = fetchedAll;
    if (all != null) {
      _userListIsAllTypes = all;
      unawaited(MetadataCache.write(
          _allTypesKey, JsonUtf8Encoder().convert(all), epoch));
    } else {
      _userListIsAllTypes = storedAll ?? false;
    }
    return types;
  }

  /// Stored next to the list, so it is cleared and rewritten with it.
  static const _allTypesKey = 'user-device-types-all';

  static bool _userListIsAllTypes = false;

  /// Whether the last list [getDeviceTypes] returned without ids is every
  /// type of the platform, because the backend has no /user-device-types.
  static bool get userListIsAllTypes => _userListIsAllTypes;

  /// Null when no usable flag is stored.
  static Future<bool?> _readStoredAllTypes() async {
    final entry = await MetadataCache.readEntry(_allTypesKey);
    if (entry == null) return null;
    try {
      final value = jsonDecode(utf8.decode(entry.bytes));
      return value is bool ? value : null;
    } catch (_) {
      return null;
    }
  }

  /// [validator] goes along only with the request of the URI it came from, so
  /// one stored from the fallback is not sent to /user-device-types. A
  /// [NotModified] carries `all` of the request that answered it.
  static Future<({MetadataFetch fetch, bool all})> _fetchUserTypesRaw(
      MetadataValidator? validator) async {
    try {
      return (fetch: await _fetchList(userUri, null, validator), all: false);
    } on UnexpectedStatusCodeException catch (e) {
      // A device-repository older than /user-device-types, or a gateway policy
      // that does not cover the path yet.
      if (e.code != 404 && e.code != 403) rethrow;
      ErrorReporter.log('user-device-types unavailable, loading all device types', e);
      return (fetch: await _fetchList(uri, null, validator), all: true);
    }
  }

  /// Always the list itself, never conditional.
  static Future<List<dynamic>> _fetchRaw(String url, List<String>? ids) async =>
      (await _fetchList(url, ids, null) as Fetched).raw;

  /// Pages through [url]. Only the first request carries [validator], and a
  /// validator is returned only for a list that came in one answer.
  static Future<MetadataFetch> _fetchList(
      String url, List<String>? ids, MetadataValidator? validator) async {
    final Map<String, String> queryParameters = {"limit": "9999"};
    if (ids != null && ids.isNotEmpty) {
      queryParameters["ids"] = ids.join(",");
    }

    final headers = await listHeaders();
    final dio = await listDio();

    final raw = <dynamic>[];
    MetadataValidator? firstValidator;
    var cont = true;
    while (cont) {
      queryParameters["offset"] = raw.length.toString();
      final requestUri = Uri.parse(url).replace(queryParameters: queryParameters);
      final first = raw.isEmpty;
      final Response<List<dynamic>?> resp;
      try {
        resp = await dio.getUri<List<dynamic>?>(requestUri,
            options: first
                ? conditionalOptions(headers, requestUri, validator)
                : Options(headers: headers));
      } on DioException catch (e) {
        checkReadStatus(e, url);
        rethrow;
      }
      if (first && resp.statusCode == 304) return const NotModified();
      final l = resp.data ?? [];
      if (first) firstValidator = validatorOf(resp);
      raw.addAll(l);
      cont = l.length == 9999 && (ids == null || ids.isNotEmpty);
    }
    return Fetched(raw, raw.length < 9999 ? firstValidator : null);
  }

  static bool isAvailable() => ApiAvailableService().isAvailable(uri);
}
