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

/// [cached7] and [cached365] serve from the Hive HTTP cache without asking the
/// backend (forceCache). Only data that may be stale for that long belongs
/// there: device types, smart-service definitions, images. Anything the user
/// expects to be current, and anything already persisted in Isar, uses
/// [standard] — a forceCache response would defeat an explicit refresh.
enum DioConfig { cached7, cached365, standard, mgwApi, mgwAuth }

class DioFactory {
  DioFactory._();

  // Memoizes the FUTURE, not the instance: with the instance-map two
  // concurrent first callers both built a Dio (each with its own HiveCacheStore
  // and HttpClient) and the loser was silently orphaned.
  static final Map<DioConfig, Future<Dio>> _instances = {};

  static Future<Dio> create(DioConfig config) =>
      _instances.putIfAbsent(config, () => _buildForConfig(config));

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
      DioConfig.standard => _buildDio(
        config,
        baseOptions: BaseOptions(
          connectTimeout: const Duration(milliseconds: 5000),
          sendTimeout: const Duration(milliseconds: 5000),
          receiveTimeout: const Duration(milliseconds: 5000),
        ),
      ),
      DioConfig.mgwApi => _buildDio(
        config,
        baseOptions: BaseOptions(
          connectTimeout: const Duration(milliseconds: 15000),
          sendTimeout: const Duration(milliseconds: 5000),
          receiveTimeout: const Duration(milliseconds: 5000),
        ),
      ),
      DioConfig.mgwAuth => _buildDio(
        config,
        baseOptions: BaseOptions(
          connectTimeout: const Duration(milliseconds: 15000),
          sendTimeout: const Duration(milliseconds: 5000),
          receiveTimeout: const Duration(milliseconds: 5000),
        ),
      ),
    };
  }

  static Dio _buildDio(DioConfig config, {CacheOptions? cacheOptions, BaseOptions? baseOptions,}) {
    return Dio(baseOptions ?? BaseOptions())
      ..interceptors.addAll([
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

