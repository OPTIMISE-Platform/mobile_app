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
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:dio_cache_interceptor_hive_store/dio_cache_interceptor_hive_store.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/services/cache_helper.dart';

import '../exceptions/unexpected_status_code_exception.dart';
import '../models/concept.dart';
import 'auth.dart';

class ConceptsService {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  static CacheOptions? _options;

  static initOptions() async {
    if (_options != null) {
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
  }

  static Future<List<Concept>> getConcepts() async {
    final List<Concept> result = [];
    bool cont = true;
    while (cont) {
      String uri = '${dotenv.env["API_URL"] ?? 'localhost'}/permissions/query/v3/resources/concepts';
      final Map<String, String> queryParameters = {};
      queryParameters["limit"] = "9999";
      queryParameters["sort"] = "name.desc";
      if (result.isNotEmpty) {
        queryParameters["after.id"] = result.last.id;
        queryParameters["after.sort_field_value"] = result.last.name;
      }

      final headers = await Auth().getHeaders();
      await initOptions();
      final dio = Dio()
        ..interceptors.add(DioCacheInterceptor(options: _options!));
      final Response<List<dynamic>?> resp;
      try {
        resp = await dio.get<List<dynamic>?>(uri, queryParameters: queryParameters, options: Options(headers: headers));
      } on DioError catch (e) {
        if (e.response?.statusCode == null || e.response!.statusCode! > 304) {
          throw UnexpectedStatusCodeException(e.response?.statusCode);
        }
        rethrow;
      }
      if (resp.statusCode == 304) {
        _logger.d("Using cached Concept");
      }

      final l = resp.data ?? [];
      cont = l.length == 9999;
      result.addAll(List<Concept>.generate(l.length, (index) => Concept.fromJson(l[index])));
    }
    return result;
  }
}