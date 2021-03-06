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
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:dio_cache_interceptor_hive_store/dio_cache_interceptor_hive_store.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/services/cache_helper.dart';

import '../exceptions/unexpected_status_code_exception.dart';
import '../models/attribute.dart';
import '../models/device_search_filter.dart';
import 'auth.dart';

class DevicesService {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );


  static late final Dio? _dio;
  static CacheOptions? _options;

  static initOptions() async {
    if (_options != null && _dio != null) {
      return;
    }

    String? cacheFile = await CacheHelper.getCacheFile();

    _options = CacheOptions(
      store: HiveCacheStore(cacheFile),
      policy: CachePolicy.refreshForceCache,
      hitCacheOnErrorExcept: [401, 403],
      maxStale: const Duration(days: 7),
      priority: CachePriority.normal,
      allowPostMethod: true,
      keyBuilder: CacheHelper.bodyCacheIDBuilder,
    );
    _dio = Dio()
      ..interceptors.add(DioCacheInterceptor(options: _options!));
  }

  static Future<List<DeviceInstance>> getDevices(int limit, int offset, DeviceSearchFilter filter) async {
    late Response<List<dynamic>?> resp;
    final headers = await Auth().getHeaders();
    await initOptions();

    final body = filter.toBody(limit, offset);
    final uri = (dotenv.env["API_URL"] ?? 'localhost') + '/permissions/query/v3/query';
    final encoded = json.encode(body);
    _logger.d("Devices: " + encoded);
    resp = await _dio!.post<List<dynamic>?>(uri, options: Options(headers: headers), data: encoded);


    if (resp.statusCode == null || resp.statusCode! > 304) {
      throw UnexpectedStatusCodeException(resp.statusCode);
    }

    if (resp.statusCode == 304) {
      _logger.d("Using cached devices");
    }

    final l = resp.data ?? [];
    return List<DeviceInstance>.generate(
        l.length, (index) => DeviceInstance.fromJson(l[index]));
  }

  static Future<void> saveDevice(DeviceInstance device) async {
    _logger.d("Saving device: " + device.id);

    final uri = (dotenv.env["API_URL"] ?? 'localhost') + '/device-manager/devices/' + device.id + "?update-only-same-origin-attributes=" + sharedOrigin + "," + appOrigin;

    final encoded = json.encode(device.toJson());

    final headers = await Auth().getHeaders();
    await initOptions();
    final resp = await _dio!.put<dynamic>(uri, options: Options(headers: headers), data: encoded);

    if (resp.statusCode == null || resp.statusCode! > 204) {
      throw UnexpectedStatusCodeException(resp.statusCode);
    }

    return;
  }

  /// Only returns an upper limit of devices, which only respects the filter.query and no further filters
  static Future<int> getTotalDevices(DeviceSearchFilter filter) async {
    String uri = (dotenv.env["API_URL"] ?? 'localhost') +
        '/permissions/query/v3/total/devices';

    final Map<String, String> queryParameters = {};
    if (filter.query.isNotEmpty) {
      queryParameters["search"] = filter.query;
    }
    final headers = await Auth().getHeaders();
    await initOptions();
    final resp = await _dio!.get<int>(uri, options: Options(headers: headers), queryParameters: queryParameters);

    if (resp.statusCode == null || resp.statusCode! > 304) {
      throw UnexpectedStatusCodeException(resp.statusCode);
    }

    if (resp.statusCode == 304) {
      _logger.d("Using cached total devices");
    }

    return resp.data ?? 0;
  }
}
