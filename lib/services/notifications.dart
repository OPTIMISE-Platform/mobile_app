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
import 'package:flutter/foundation.dart';
import 'package:http_cache_hive_store/http_cache_hive_store.dart';import 'package:logger/logger.dart';
import 'package:mobile_app/models/notification.dart' as app;
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/exceptions/unexpected_status_code_exception.dart';
import 'package:mobile_app/shared/dio_factory.dart';
import 'package:mobile_app/services/api_available.dart';
import 'package:mobile_app/services/auth.dart';

class NotificationsService {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  static late final Dio? _dio;
  static final baseUrl =
      '${Settings.getApiUrl() ?? 'localhost'}/notifications-v2/notifications';

  static initOptions() async {
    _dio = await DioFactory.create(DioConfig.cached7);
  }

  static Future<app.NotificationResponse?> getNotifications(
      int limit, int offset) async {
    String uri =
        "$baseUrl?limit=${limit.toString()}&offset=${offset.toString()}&channel=push";

    final headers = await Auth().getHeaders();
    await initOptions();
    final Response<Map<String, dynamic>> resp;
    try {
      resp = await _dio!
          .get<Map<String, dynamic>>(uri, options: Options(headers: headers));
    } on DioException catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 304) {
        throw UnexpectedStatusCodeException(
            e.response?.statusCode, "$uri ${e.message}");
      }
      rethrow;
    }
    if (resp.statusCode == 304) {
      _logger.d("Using cached notifications");
    }

    if (resp.data == null) {
      return null;
    }

    final data = resp.data!;
    // Parse a large notification page (up to limit=10000) off the UI thread;
    // small pages inline to avoid the isolate spawn costing more than the work.
    final count = (data['notifications'] as List?)?.length ?? 0;
    return count > _isolateParseThreshold
        ? await compute(_parseNotificationResponse, data)
        : app.NotificationResponse.fromJson(data);
  }

  static Future setNotification(app.Notification notification) async {
    final url = '$baseUrl/${notification.id}';

    final headers = await Auth().getHeaders();
    await initOptions();

    final resp = await _dio!.put(url,
        options: Options(headers: headers), data: json.encode(notification));

    if (resp.statusCode == null || resp.statusCode! > 201) {
      throw UnexpectedStatusCodeException(resp.statusCode, url);
    }
  }

  static Future deleteNotifications(List<String> ids) async {
    final headers = await Auth().getHeaders();
    await initOptions();
    final resp = await _dio!.delete(baseUrl,
        options: Options(headers: headers), data: json.encode(ids));

    if (resp.statusCode == null || resp.statusCode! > 204) {
      throw UnexpectedStatusCodeException(resp.statusCode, baseUrl);
    }
  }

  static bool isAvailable() => ApiAvailableService().isAvailable(baseUrl);
}

/// Above this many notifications in one response, parse in a background isolate.
const _isolateParseThreshold = 500;

app.NotificationResponse _parseNotificationResponse(Map<String, dynamic> json) =>
    app.NotificationResponse.fromJson(json);
