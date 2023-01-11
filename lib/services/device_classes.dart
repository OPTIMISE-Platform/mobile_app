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
import 'package:mobile_app/models/device_class.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/services/settings.dart';

import '../exceptions/unexpected_status_code_exception.dart';
import '../shared/http_client_adapter.dart';
import 'auth.dart';

class DeviceClassesService {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  static CacheOptions? _options;

  static initOptions() async {
    if (_options != null) {
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
  }

  static Future<List<DeviceClass>> getDeviceClasses() async {
    String uri = '${Settings.getApiUrl() ?? 'localhost'}/api-aggregator/device-class-uses';
    final Map<String, String> queryParameters = {};

    final headers = await Auth().getHeaders();
    await initOptions();
    final dio = Dio(BaseOptions(connectTimeout: 1500, sendTimeout: 5000, receiveTimeout: 5000))
      ..interceptors.add(DioCacheInterceptor(options: _options!))
      ..httpClientAdapter = AppHttpClientAdapter();
    final Response<Map<String, dynamic>?> resp;
    try {
      resp = await dio.get<Map<String, dynamic>?>(uri, queryParameters: queryParameters, options: Options(headers: headers));
    } on DioError catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 304) {
        throw UnexpectedStatusCodeException(e.response?.statusCode, uri);
      }
      rethrow;
    }
    if (resp.statusCode == 304) {
      _logger.d("Using cached device classes");
    }
    if (resp.data == null) return [];

    final l = resp.data!["device-classes"];
    if (l == null) return [];
    final deviceClasses = List<DeviceClass>.generate(l.length, (index) => DeviceClass.fromJson(l[index]));
    for (var element in deviceClasses) {
      for (var s in (resp.data!["used-devices"][element.id] as List<dynamic>)) {
        element.deviceIds.add(s as String);
      }
    }
    return deviceClasses;
  }
}
