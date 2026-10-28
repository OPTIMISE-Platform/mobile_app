/*
 * Copyright (c) 2026 InfAI (CC SES)
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
import 'package:flutter/foundation.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/dio_factory.dart';
import 'package:mobile_app/shared/dio_status.dart';

/// Client for process-io, the key-value variables that processes and clients
/// share. A variable is addressed by its key; the key is percent-encoded into
/// the path.
class ProcessIoService {
  static String get baseUrl => '${Settings.getApiUrl() ?? 'localhost'}/process-io';

  static String _variableUrl(String key) => '$baseUrl/variables/${Uri.encodeComponent(key)}';

  /// The variable stored under [key], or null when there is none.
  static Future<Map<String, dynamic>?> getVariable(String key) async {
    final url = _variableUrl(key);
    final headers = await Auth().getHeaders();
    final dio = await DioFactory.create(DioConfig.standard);
    final Response<Map<String, dynamic>> resp;
    try {
      resp = await dio.get<Map<String, dynamic>>(url, options: Options(headers: headers));
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      checkReadStatus(e, url);
      rethrow;
    }
    return storedVariable(resp.data);
  }

  /// process-io answers an unknown key with 200 and `{"key": ..., "value": null}`
  /// rather than 404, so a variable without a value counts as missing.
  @visibleForTesting
  static Map<String, dynamic>? storedVariable(Map<String, dynamic>? body) => body?["value"] == null ? null : body;

  @visibleForTesting
  static Map<String, dynamic> variableBody(String key, dynamic value, {String instanceId = ""}) => {
        "key": key,
        "value": value,
        "process_definition_id": "",
        "process_instance_id": instanceId,
        "unix_timestamp_in_s": DateTime.now().millisecondsSinceEpoch ~/ 1000,
      };

  /// Stores [value] under [key], replacing a variable that exists. With [instanceId] the variable is bound to
  /// that instance and is deleted together with it.
  static Future<void> setVariable(String key, dynamic value, {String instanceId = ""}) async {
    final url = _variableUrl(key);
    final body = variableBody(key, value, instanceId: instanceId);
    final headers = await Auth().getHeaders();
    final dio = await DioFactory.create(DioConfig.standard);
    try {
      await dio.put<dynamic>(url, options: Options(headers: headers), data: json.encode(body));
    } on DioException catch (e) {
      checkWriteStatus(e, url);
      rethrow;
    }
  }

  static Future<void> deleteVariable(String key) async {
    final url = _variableUrl(key);
    final headers = await Auth().getHeaders();
    final dio = await DioFactory.create(DioConfig.standard);
    try {
      await dio.delete<dynamic>(url, options: Options(headers: headers));
    } on DioException catch (e) {
      checkWriteStatus(e, url);
      rethrow;
    }
  }
}
