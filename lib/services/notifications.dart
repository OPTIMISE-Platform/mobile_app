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
import 'package:logger/logger.dart';
import 'package:mobile_app/models/notification.dart' as app;
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/api_available_interceptor.dart';

import 'package:mobile_app/exceptions/unexpected_status_code_exception.dart';
import 'package:mobile_app/shared/http_client_adapter.dart';
import 'package:mobile_app/services/api_available.dart';
import 'package:mobile_app/services/auth.dart';

class NotificationsService {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  static CacheOptions? _options;
  static late final Dio? _dio;
  static final baseUrl = '${Settings.getApiUrl() ?? 'localhost'}/notifications-v2/notifications';

  static initOptions() async {
    if (_options != null && _dio != null) {
      return;
    }

    _options = CacheOptions(
      store: HiveCacheStore(await CacheHelper.getCacheFile()),
      policy: CachePolicy.refreshForceCache,
      hitCacheOnErrorExcept: [401, 403],
      maxStale: const Duration(days: 7),
      priority: CachePriority.normal,
      keyBuilder: CacheHelper.bodyCacheIDBuilder,
    );

    _dio = Dio(BaseOptions(connectTimeout: 1500, sendTimeout: 5000, receiveTimeout: 5000))
      ..interceptors.add(DioCacheInterceptor(options: _options!))
      ..interceptors.add(ApiAvailableInterceptor())
      ..httpClientAdapter = AppHttpClientAdapter();
  }

  static Future<app.NotificationResponse?> getNotifications(int limit, int offset) async {
    String uri =
        "$baseUrl?limit=${limit.toString()}&offset=${offset.toString()}";

    final headers = await Auth().getHeaders();
    await initOptions();
    final Response<Map<String, dynamic>> resp;
    try {
      resp = await _dio!.get<Map<String, dynamic>>(uri, options: Options(headers: headers));
    } on DioError catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 304) {
        throw UnexpectedStatusCodeException(e.response?.statusCode, "$uri ${e.message}");
      }
      rethrow;
    }
    if (resp.statusCode == 304) {
      _logger.d("Using cached notifications");
    }

    if (resp.data == null) {
      return null;
    }

    return app.NotificationResponse.fromJson(resp.data!);
  }

  static Future setNotification(app.Notification notification) async {
    final url = '$baseUrl/${notification.id}';

    final headers = await Auth().getHeaders();
    await initOptions();

    final resp = await _dio!.put(url, options: Options(headers: headers), data: json.encode(notification));

    if (resp.statusCode == null || resp.statusCode! > 201) {
      throw UnexpectedStatusCodeException(resp.statusCode, url);
    }
  }

  static Future deleteNotifications(List<String> ids) async {

    final headers = await Auth().getHeaders();
    await initOptions();
    final resp = await _dio!.delete(baseUrl, options: Options(headers: headers), data: json.encode(ids));

    if (resp.statusCode == null || resp.statusCode! > 204) {
      throw UnexpectedStatusCodeException(resp.statusCode, baseUrl);
    }
  }

  static bool isAvailable() => ApiAvailableService().isAvailable(baseUrl);

}
