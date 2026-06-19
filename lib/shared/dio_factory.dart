/*
 * Copyright 2026 InfAI (CC SES)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */

import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter/foundation.dart';
import 'package:http_cache_hive_store/http_cache_hive_store.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import '../services/cache_helper.dart';
import 'api_available_interceptor.dart';
import 'http_client_adapter.dart';

enum DioConfig { cached7,cached7withPost, cached365,standard}

class DioFactory {
  DioFactory._();

  static final Map<DioConfig, Dio> _instances = {};

  static Future<Dio> create(DioConfig config) async {
    if (_instances.containsKey(config)) return _instances[config]!;

    final dio = await _buildForConfig(config);
    _instances[config] = dio;
    return dio;
  }

  static Future<Dio> _buildForConfig(DioConfig config) async {
    return switch (config) {
      DioConfig.cached7 => _buildDio(
        config,
        cacheOptions: CacheOptions(
          store: HiveCacheStore(await CacheHelper.getCacheFile()),
          policy: CachePolicy.forceCache,
          maxStale: const Duration(days: 7),
          priority: CachePriority.normal,
          keyBuilder: CacheHelper.newCacheKeyBuilder,
        ),
        baseOptions: BaseOptions(
          connectTimeout: const Duration(milliseconds: 5000),
          sendTimeout: const Duration(milliseconds: 5000),
          receiveTimeout: const Duration(milliseconds: 5000),
        ),
      ),
      DioConfig.cached365 => _buildDio(
        config,
        cacheOptions: CacheOptions(
          store: HiveCacheStore(await CacheHelper.getCacheFile()),
          policy: CachePolicy.forceCache,
          maxStale: const Duration(days: 365),
          priority: CachePriority.normal,
          keyBuilder: CacheHelper.newCacheKeyBuilder,
        ),
        baseOptions: BaseOptions(
          connectTimeout: const Duration(milliseconds: 5000),
          sendTimeout: const Duration(milliseconds: 5000),
          receiveTimeout: const Duration(milliseconds: 5000),
        ),
      ),
      DioConfig.cached7withPost => _buildDio(
        config,
        cacheOptions: CacheOptions(
            store: HiveCacheStore(await CacheHelper.getCacheFile()),
            policy: CachePolicy.forceCache,
            maxStale: const Duration(days: 7),
            priority: CachePriority.normal,
            keyBuilder: CacheHelper.newCacheKeyBuilder,
            allowPostMethod: true
        ),
        baseOptions: BaseOptions(
          connectTimeout: const Duration(milliseconds: 1500),
          sendTimeout: const Duration(milliseconds: 5000),
          receiveTimeout: const Duration(milliseconds: 5000),
        ),
      ),
      DioConfig.standard => _buildDio(
        config,
        baseOptions: BaseOptions(
          connectTimeout: const Duration(milliseconds: 5000),
          sendTimeout: const Duration(milliseconds: 5000),
          receiveTimeout: const Duration(milliseconds: 5000),
        ),
      ),
    };
  }

  static void setHeaders(DioConfig config, Map<String, String> headers) {
    final dio = _instances[config];
    if (dio == null) return;
    dio.options.headers.addAll(headers);
  }

  static void clearHeaders(DioConfig config, List<String> keys) {
    final dio = _instances[config];
    if (dio == null) return;
    for (final key in keys) {
      dio.options.headers.remove(key);
    }
  }

  static Dio _buildDio(DioConfig config, {CacheOptions? cacheOptions, BaseOptions? baseOptions,Map<String, String> Function()? getHeaders,}) {
    return Dio(baseOptions ?? BaseOptions())
      ..interceptors.addAll([
        if (getHeaders != null) DynamicHeadersInterceptor(getHeaders),
        if (cacheOptions != null) DioCacheInterceptor(options: cacheOptions),
        ApiAvailableInterceptor(),
        if (kDebugMode) ...[
          _InstanceLogInterceptor(config.name),
          PrettyDioLogger(
            requestHeader: false,
            requestBody: false,
            responseBody: false,
            request: false,
          ),
        ],
      ])
      ..httpClientAdapter = AppHttpClientAdapter();
  }
}
class _InstanceLogInterceptor extends Interceptor {
  const _InstanceLogInterceptor(this.key);

  final String key;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    debugPrint('🔌 Dio instance: "$key" → ${options.method} ${options.uri}');
    handler.next(options);
  }
}

class DynamicHeadersInterceptor extends Interceptor {
  const DynamicHeadersInterceptor(this._getHeaders);

  final Map<String, String> Function() _getHeaders;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers.addAll(_getHeaders());
    handler.next(options);
  }
}
