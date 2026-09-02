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

import 'package:dio/dio.dart';
import 'package:mobile_app/shared/dio_status.dart';
import 'package:mobile_app/models/function.dart';
import 'package:mobile_app/shared/metadata_cache.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/dio_factory.dart';
import 'package:mobile_app/services/api_available.dart';
import 'package:mobile_app/services/auth.dart';

class FunctionsService {
  static String uri =
      '${Settings.getApiUrl() ?? 'localhost'}/device-repository/functions';

  static Future<List<PlatformFunction>> getFunctions(
      {Duration maxAge = metadataMaxAge}) async {
    return loadMetadataCached('functions', _fetchRaw, PlatformFunction.fromJson,
        maxAge: maxAge);
  }

  static Future<List<dynamic>> _fetchRaw() async {
    final headers = await Auth().getHeaders();
    // Uncached dio — persisted via MetadataCache (Isar) instead of Hive.
    final dio = await DioFactory.create(DioConfig.standard);

    final Map<String, String> queryParameters = {"limit": "9999"};
    final raw = <dynamic>[];
    var cont = true;
    while (cont) {
      queryParameters["offset"] = raw.length.toString();
      final Response<List<dynamic>?> resp;
      try {
        resp = await dio.get<List<dynamic>?>(uri,
            options: Options(headers: headers), queryParameters: queryParameters);
      } on DioException catch (e) {
        checkReadStatus(e, uri);
        rethrow;
      }
      final l = resp.data ?? [];
      raw.addAll(l);
      cont = l.length == 9999;
    }
    return raw;
  }

  static bool isAvailable() => ApiAvailableService().isAvailable(uri);
}
