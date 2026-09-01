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
import 'package:logger/logger.dart';
import 'package:mobile_app/models/device_class.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/dio_factory.dart';
import 'package:mobile_app/shared/metadata_cache.dart';
import 'package:mobile_app/services/api_available.dart';
import 'package:mobile_app/services/auth.dart';

class DeviceClassesService {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  static String uri =
      '${Settings.getApiUrl() ?? 'localhost'}/api-aggregator/device-class-uses';

  /// Cache key for the last successful response, see [getDeviceClasses].
  static const _cacheKey = 'device-class-uses';

  /// Which device belongs to which class. Unlike the other reference metadata
  /// this is not stable — a newly added device has to show up under its class —
  /// so it is fetched fresh and the last successful response is kept only as a
  /// fallback for an unreachable backend. It used to sit on the shared 7-day
  /// force-cache, which never asked the backend again at all.
  static Future<List<DeviceClass>> getDeviceClasses() async {
    final Map<String, String> queryParameters = {};

    Map<String, dynamic>? data;
    try {
      final headers = await Auth().getHeaders();
      final dio = await DioFactory.create(DioConfig.standard);
      final resp = await dio.get<Map<String, dynamic>?>(uri,
          queryParameters: queryParameters, options: Options(headers: headers));
      data = resp.data;
      if (data != null) {
        unawaited(MetadataCache.write(
            _cacheKey, JsonUtf8Encoder().convert(data)));
      }
    } catch (e) {
      // Offline, local mode or a failing backend: fall back to the last
      // response we saw rather than reporting "no device classes", which
      // disables the classes tab.
      final cached = await MetadataCache.read(_cacheKey, const Duration(days: 7));
      if (cached == null) rethrow;
      _logger.d("Using cached device classes: $e");
      data = jsonDecode(utf8.decode(cached)) as Map<String, dynamic>;
    }
    if (data == null) return [];

    final l = data["device-classes"];
    if (l == null) return [];
    final deviceClasses = List<DeviceClass>.generate(
        l.length, (index) => DeviceClass.fromJson(l[index]));
    for (var element in deviceClasses) {
      for (var s in (data["used-devices"][element.id] as List<dynamic>? ?? [])) {
        element.deviceIds.add(s as String);
      }
    }
    return deviceClasses;
  }

  static bool isAvailable() => ApiAvailableService().isAvailable(uri);
}
