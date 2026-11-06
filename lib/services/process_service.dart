/*
 * Copyright 2026 InfAI (CC SES)
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

import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:mobile_app/models/process.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/dio_factory.dart';
import 'package:mobile_app/shared/dio_status.dart';

/// Read-only access to the process engine (`automation-engine`, namespace
/// `processes`).
class ProcessService {
  static String get baseUrl =>
      '${Settings.getApiUrl() ?? 'localhost'}/automation-engine/namespaces/processes';

  static const _pageSize = 100;

  static Future<List<ProcessDeployment>> getDeployments() async {
    final items = await _getAll("$baseUrl/deployments");
    return items.map(ProcessDeployment.fromJson).toList();
  }

  static Future<List<ProcessInstance>> getInstances() async {
    final items = await _getAll("$baseUrl/instances");
    return items.map(ProcessInstance.fromJson).toList();
  }

  static Future<ProcessDebug> getDebug(String instanceId) async {
    final url = "$baseUrl/instances/$instanceId/debug";
    final data = await _get(url);
    if (data is! Map) {
      throw FormatException("Unexpected answer from $url");
    }
    return ProcessDebug.fromJson(Map<String, dynamic>.from(data));
  }

  /// Reads a list endpoint page by page until `total` items are in. A page
  /// that comes back empty ends the loop as well, so a `total` that is too
  /// high cannot make it spin.
  static Future<List<Map<String, dynamic>>> _getAll(String url) async {
    final all = <Map<String, dynamic>>[];
    while (true) {
      final data = await _get(url, {"limit": _pageSize, "offset": all.length});
      if (data is! Map) {
        throw FormatException("Unexpected answer from $url");
      }
      final items = data["items"];
      final page = <Map<String, dynamic>>[
        if (items is List)
          for (final e in items)
            if (e is Map) Map<String, dynamic>.from(e)
      ];
      all.addAll(page);
      final total = data["total"];
      if (page.isEmpty || (total is int && all.length >= total)) break;
    }
    return all;
  }

  static Future<dynamic> _get(String url,
      [Map<String, dynamic>? queryParameters]) async {
    final headers = await Auth().getHeaders();
    final dio = await DioFactory.create(DioConfig.standard);
    try {
      final resp = await dio.get<dynamic>(url,
          queryParameters: queryParameters,
          options: Options(headers: headers));
      return resp.data;
    } on DioException catch (e) {
      checkReadStatus(e, url);
      rethrow;
    }
  }

  /// Runs [action] for every item with at most [maxInFlight] running at once.
  /// An item whose action throws does not stop the others; [action] handles
  /// its own errors.
  static Future<void> forEachLimited<T>(Iterable<T> items, int maxInFlight,
      Future<void> Function(T item) action) async {
    final queue = items.iterator;
    Future<void> worker() async {
      while (queue.moveNext()) {
        final item = queue.current;
        try {
          await action(item);
        } catch (_) {}
      }
    }

    await Future.wait(List.generate(
        math.max(1, maxInFlight), (_) => worker()));
  }
}
