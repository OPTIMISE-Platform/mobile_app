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
import 'package:mobile_app/exceptions/unexpected_status_code_exception.dart';
import 'package:mobile_app/models/db_query.dart';
import 'package:mobile_app/services/settings.dart';

import '../shared/api_available_interceptor.dart';
import 'auth.dart';

class DbQueryService {
  static final _dio = Dio(BaseOptions(
      connectTimeout: 1500, sendTimeout: 5000, receiveTimeout: 15000))
    ..interceptors.add(ApiAvailableInterceptor());

  static Future<List<List<dynamic>>> query(DbQuery query) async {
    final url = '${Settings.getApiUrl() ?? 'localhost'}/db/v3/queries';
    final headers = await Auth().getHeaders();

    final resp = await _dio.post<List<dynamic>>(url, options: Options(headers: headers), data: json.encode([query]));
    if (resp.statusCode == null || resp.data == null || resp.statusCode != 200) {
      throw UnexpectedStatusCodeException(resp.statusCode, url);
    }
    final decoded = resp.data![0];
    return List<List<dynamic>>.generate(decoded.length, (i) => decoded[i] as List<dynamic>);
  }
}
