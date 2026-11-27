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
import 'package:mobile_app/shared/conditional_get.dart';
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
      {Duration maxAge = metadataMaxAge,
      void Function(DateTime storedAt)? serveStale}) async {
    return loadMetadataCached('functions', _fetchRaw, PlatformFunction.fromJson,
        maxAge: maxAge, serveStale: serveStale);
  }

  static Future<MetadataFetch> _fetchRaw(MetadataValidator? validator) async {
    final headers = await Auth().getHeaders();
    // Uncached dio — persisted via MetadataCache (Isar) instead of Hive.
    final dio = await DioFactory.create(DioConfig.standard);

    final Map<String, String> queryParameters = {"limit": "9999"};
    final raw = <dynamic>[];
    MetadataValidator? firstValidator;
    var cont = true;
    while (cont) {
      queryParameters["offset"] = raw.length.toString();
      final requestUri =
          Uri.parse(uri).replace(queryParameters: queryParameters);
      final first = raw.isEmpty;
      final Response<List<dynamic>?> resp;
      try {
        // Only the first request is conditional: a 304 on it would say
        // nothing about the pages behind it.
        resp = await dio.getUri<List<dynamic>?>(requestUri,
            options: first
                ? conditionalOptions(headers, requestUri, validator)
                : Options(headers: headers));
      } on DioException catch (e) {
        checkReadStatus(e, uri);
        rethrow;
      }
      if (first && resp.statusCode == 304) return const NotModified();
      final l = resp.data ?? [];
      if (first) firstValidator = validatorOf(resp);
      raw.addAll(l);
      cont = l.length == 9999;
    }
    // A validator only covers a list that came in one answer.
    return Fetched(raw, raw.length < 9999 ? firstValidator : null);
  }

  static bool isAvailable() => ApiAvailableService().isAvailable(uri);
}
