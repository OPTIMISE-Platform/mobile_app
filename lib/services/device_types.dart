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

import 'package:dio/dio.dart';
import 'package:mobile_app/exceptions/unexpected_status_code_exception.dart';
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

  /// Without [ids], the device types of the devices the user can see, own or
  /// shared, not every type on the platform.
  static Future<List<DeviceType>> getDeviceTypes([List<String>? ids,
      Duration maxAge = metadataMaxAge]) async {
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
    return loadMetadataCached(
        'user-device-types', _fetchUserTypesRaw, DeviceType.fromJson,
        maxAge: maxAge);
  }

  static Future<List<dynamic>> _fetchUserTypesRaw() async {
    try {
      return await _fetchRaw(userUri, null);
    } on UnexpectedStatusCodeException catch (e) {
      // A device-repository older than /user-device-types, or a gateway policy
      // that does not cover the path yet.
      if (e.code != 404 && e.code != 403) rethrow;
      ErrorReporter.log('user-device-types unavailable, loading all device types', e);
      return _fetchRaw(uri, null);
    }
  }

  static Future<List<dynamic>> _fetchRaw(String url, List<String>? ids) async {
    final Map<String, String> queryParameters = {"limit": "9999"};
    if (ids != null && ids.isNotEmpty) {
      queryParameters["ids"] = ids.join(",");
    }

    final headers = await Auth().getHeaders();
    // Plain (uncached) dio — metadata is persisted via MetadataCache instead of
    // the Hive HTTP cache, whose per-read CRC32 blocked the UI isolate.
    final dio = await DioFactory.create(DioConfig.standard);

    final raw = <dynamic>[];
    var cont = true;
    while (cont) {
      queryParameters["offset"] = raw.length.toString();
      final Response<List<dynamic>?> resp;
      try {
        resp = await dio.get<List<dynamic>?>(url,
            queryParameters: queryParameters, options: Options(headers: headers));
      } on DioException catch (e) {
        checkReadStatus(e, url);
        rethrow;
      }
      final l = resp.data ?? [];
      raw.addAll(l);
      cont = l.length == 9999 && (ids == null || ids.isNotEmpty);
    }
    return raw;
  }

  static bool isAvailable() => ApiAvailableService().isAvailable(uri);
}
