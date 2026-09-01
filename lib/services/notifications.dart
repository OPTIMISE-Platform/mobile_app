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
import 'package:logger/logger.dart';
import 'package:mobile_app/models/notification.dart' as app;
import 'package:isar_community/isar.dart';
import 'package:mobile_app/shared/chunked_parse.dart';
import 'package:mobile_app/shared/isar.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/exceptions/unexpected_status_code_exception.dart';
import 'package:mobile_app/shared/dio_factory.dart';
import 'package:mobile_app/services/api_available.dart';
import 'package:mobile_app/services/auth.dart';

class NotificationsService {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  static final baseUrl =
      '${Settings.getApiUrl() ?? 'localhost'}/notifications-v2/notifications';

  static Future<app.NotificationResponse?> getNotifications(
      int limit, int offset) async {
    String uri =
        "$baseUrl?limit=${limit.toString()}&offset=${offset.toString()}&channel=push";

    final headers = await Auth().getHeaders();
    final dio = await DioFactory.create(DioConfig.standard);
    final Response<Map<String, dynamic>> resp;
    try {
      resp = await dio
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
    // Parse the notification list (up to limit=10000) in yielding chunks so a
    // large page doesn't block the UI isolate, then assemble the response.
    final notifications = await parseListChunked(
        (data['notifications'] as List<dynamic>? ?? []),
        app.Notification.fromJson);
    return app.NotificationResponse(
      notifications,
      (data['offset'] as num?)?.toInt() ?? 0,
      (data['limit'] as num?)?.toInt() ?? 0,
      (data['total'] as num?)?.toInt() ?? 0,
    );
  }

  static Future setNotification(app.Notification notification) async {
    final url = '$baseUrl/${notification.id}';

    final headers = await Auth().getHeaders();
    final dio = await DioFactory.create(DioConfig.standard);

    final resp = await dio.put(url,
        options: Options(headers: headers), data: json.encode(notification));

    if (resp.statusCode == null || resp.statusCode! > 201) {
      throw UnexpectedStatusCodeException(resp.statusCode, url);
    }
  }

  static Future deleteNotifications(List<String> ids) async {
    final headers = await Auth().getHeaders();
    final dio = await DioFactory.create(DioConfig.standard);
    final resp = await dio.delete(baseUrl,
        options: Options(headers: headers), data: json.encode(ids));

    if (resp.statusCode == null || resp.statusCode! > 204) {
      throw UnexpectedStatusCodeException(resp.statusCode, baseUrl);
    }
  }

  /// Replaces the persisted set with [notifications]. The server is the source
  /// of truth, so a successful fetch defines what is stored — entries deleted
  /// on the backend disappear here too.
  static Future<void> persist(List<app.Notification> notifications) async {
    final db = isar;
    if (db == null) return;
    try {
      await db.writeTxn(() async {
        await db.notifications.clear();
        await db.notifications.putAll(notifications);
      });
    } catch (e) {
      // Best-effort mirror; a failed write must not fail the fetch.
      _logger.w("Could not persist notifications: $e");
    }
  }

  /// The last persisted set, oldest first to match the order the list expects.
  static Future<List<app.Notification>> loadPersisted() async {
    final db = isar;
    if (db == null) return [];
    try {
      final stored = await db.notifications.where().findAll();
      stored.sort((a, b) => a.created_at.compareTo(b.created_at));
      return stored;
    } catch (e) {
      _logger.w("Could not read persisted notifications: $e");
      return [];
    }
  }

  /// Drops [ids] from the persisted set after they were deleted on the backend.
  static Future<void> removePersisted(List<String> ids) async {
    final db = isar;
    if (db == null) return;
    try {
      await db.writeTxn(() =>
          db.notifications.deleteAll(ids.map(fastHash).toList(growable: false)));
    } catch (e) {
      _logger.w("Could not remove persisted notifications: $e");
    }
  }

  static bool isAvailable() => ApiAvailableService().isAvailable(baseUrl);
}
