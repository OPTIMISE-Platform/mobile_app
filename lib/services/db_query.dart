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
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/shared/dio_factory.dart';

class DbQueryService {

  static Future<List<List<dynamic>>> query(DbQuery query) async {
    final url = '${Settings.getApiUrl() ?? 'localhost'}/db/v3/queries';
    final headers = await Auth().getHeaders();

    final dio = await DioFactory.create(DioConfig.standard);
    final resp = await dio.post<List<dynamic>>(url, options: Options(headers: headers), data: json.encode([query]));
    if (resp.statusCode == null || resp.data == null || resp.statusCode != 200) {
      throw UnexpectedStatusCodeException(resp.statusCode, url);
    }
    final decoded = resp.data![0];
    return List<List<dynamic>>.generate(decoded.length, (i) => decoded[i] as List<dynamic>);
  }

  /// The newest value of [columnName] in the export [exportId], or null when
  /// the export has no row. Unlike [query], it does not need a time range, so a
  /// value that has not changed for a long time is still found.
  static Future<dynamic> lastValue(String exportId, String columnName) async {
    final url = '${Settings.getApiUrl() ?? 'localhost'}/db/v3/last-values';
    final headers = await Auth().getHeaders();

    final dio = await DioFactory.create(DioConfig.standard);
    final resp = await dio.post<List<dynamic>>(url,
        options: Options(headers: headers),
        data: json.encode([
          {"exportId": exportId, "columnName": columnName}
        ]));
    if (resp.statusCode == null || resp.data == null || resp.statusCode != 200) {
      throw UnexpectedStatusCodeException(resp.statusCode, url);
    }
    if (resp.data!.isEmpty) return null;
    final pair = resp.data!.first as Map<String, dynamic>?;
    return pair?["value"];
  }
}
