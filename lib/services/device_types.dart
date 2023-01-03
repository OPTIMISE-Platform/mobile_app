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

import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:dio_cache_interceptor_hive_store/dio_cache_interceptor_hive_store.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mutex/mutex.dart';

import '../exceptions/unexpected_status_code_exception.dart';
import '../shared/http_client_adapter.dart';
import 'auth.dart';

class DeviceTypesService {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  static CacheOptions? _options;
  static late final Dio? _dio;

  static Mutex m = Mutex();

  static initOptions() async {
    return await m.protect(() async {
      if (_options != null && _dio != null) {
        return;
      }

      _options = CacheOptions(
        store: HiveCacheStore(await CacheHelper.getCacheFile()),
        policy: CachePolicy.forceCache,
        hitCacheOnErrorExcept: [401, 403],
        maxStale: const Duration(days: 7),
        priority: CachePriority.normal,
        keyBuilder: CacheHelper.bodyCacheIDBuilder,
      );

      _dio = Dio(BaseOptions(connectTimeout: 1500, sendTimeout: 5000, receiveTimeout: 5000))
        ..interceptors.add(DioCacheInterceptor(options: _options!))
        ..httpClientAdapter = AppHttpClientAdapter();
    });
  }

  static Future<DeviceType?> getDeviceType(String id) async {
    String uri = '${Settings.getApiUrl() ?? 'localhost'}/device-manager/device-types/$id';

    final headers = await Auth().getHeaders();
    await initOptions();
    final Response<Map<String, dynamic>> resp;
    try {
      resp = await _dio!.get<Map<String, dynamic>>(uri, options: Options(headers: headers));
    } on DioError catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 304) {
        throw UnexpectedStatusCodeException(e.response?.statusCode);
      }
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
}
