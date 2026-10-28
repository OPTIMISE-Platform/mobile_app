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
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/dio_factory.dart';
import 'package:mobile_app/shared/dio_status.dart';

/// A module of a smart-service instance as the automation-engine lists it.
/// [keys] are the module's keys; a module that the engine deployed under a key
/// carries it here.
class AutomationModule {
  final String id;
  final List<String> keys;

  /// The module data the listing carries; null when it carries none.
  final Map<String, dynamic>? moduleData;

  AutomationModule(this.id, this.keys, {this.moduleData});

  factory AutomationModule.fromJson(Map<String, dynamic> json) {
    final keys = (json["keys"] as List<dynamic>?) ?? const [];
    final data = json["module_data"];
    return AutomationModule(json["id"] as String, keys.map((k) => k as String).toList(),
        moduleData: data is Map<String, dynamic> ? data : null);
  }
}

/// Client for the automation-engine's smart-services namespace. Unlike
/// [SmartServiceService], which runs on the smart-service-repository, this
/// namespace starts maintenance procedures and removes single modules.
class AutomationEngineService {
  static String get baseUrl =>
      '${Settings.getApiUrl() ?? 'localhost'}/automation-engine/namespaces/smart-services';

  /// Starts the maintenance procedure [procedure] of [instanceId]. Every
  /// variable is a string; a JSON value goes in as its JSON text.
  static Future<void> startProcedure(String instanceId, String procedure, Map<String, String> variables) async {
    final url = '$baseUrl/instances/$instanceId/maintenance-procedures/$procedure/start';
    final headers = await Auth().getHeaders();
    final dio = await DioFactory.create(DioConfig.standard);
    try {
      await dio.post<dynamic>(url,
          options: Options(headers: headers), data: json.encode({"variables": variables}));
    } on DioException catch (e) {
      checkWriteStatus(e, url);
      rethrow;
    }
  }

  /// The modules of [instanceId] with [moduleType], all pages.
  static Future<List<AutomationModule>> listModules({
    required String instanceId,
    required String moduleType,
  }) async {
    final url = '$baseUrl/modules';
    const limit = 100;
    final modules = <AutomationModule>[];
    var offset = 0;
    while (true) {
      final queryParameters = {
        "instance_id": instanceId,
        "module_type": moduleType,
        "limit": limit.toString(),
        "offset": offset.toString(),
      };
      final headers = await Auth().getHeaders();
      final dio = await DioFactory.create(DioConfig.standard);
      final Response<dynamic> resp;
      try {
        resp = await dio.get<dynamic>(url,
            queryParameters: queryParameters, options: Options(headers: headers));
      } on DioException catch (e) {
        checkReadStatus(e, url);
        rethrow;
      }
      final body = resp.data as Map<String, dynamic>;
      final items = (body["items"] as List<dynamic>?) ?? const [];
      modules.addAll(items.map((i) => AutomationModule.fromJson(i as Map<String, dynamic>)));
      offset += items.length;
      final total = body["total"] as int?;
      if (items.length < limit || (total != null && offset >= total)) break;
    }
    return modules;
  }

  /// Removes the module [moduleId] of the instance, and with it the deployment
  /// it carries.
  static Future<void> deleteModule(String moduleId) async {
    final url = '$baseUrl/modules/$moduleId';
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
