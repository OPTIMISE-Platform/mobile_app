import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:flutter/foundation.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import 'api_available_interceptor.dart';
import 'http_client_adapter.dart';

class DioFactory {
  static Dio create({CacheOptions? cacheOptions, BaseOptions? baseOptions}) {
    return Dio(baseOptions ?? BaseOptions())
      ..interceptors.addAll([
        if (cacheOptions != null) DioCacheInterceptor(options: cacheOptions),
        ApiAvailableInterceptor(),
        if (kDebugMode)
          PrettyDioLogger(
            requestHeader: false,
            requestBody: false,
            responseBody: false,
          ),
      ])
      ..httpClientAdapter = AppHttpClientAdapter();
  }
}

class _NoOpInterceptor extends Interceptor {}
