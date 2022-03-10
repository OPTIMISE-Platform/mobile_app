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
import 'package:flutter/cupertino.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/function.dart';
import 'package:mobile_app/services/cache_helper.dart';

import 'auth.dart';
import '../exceptions/unexpected_status_code_exception.dart';

class FunctionsService {
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
      policy: CachePolicy.forceCache,
      hitCacheOnErrorExcept: [401, 403],
      maxStale: const Duration(days: 7),
      priority: CachePriority.normal,
      keyBuilder: CacheHelper.bodyCacheIDBuilder,
    );
  }

  static Future<List<NestedFunction>> getNestedFunctions(BuildContext context, AppState state) async {
    String uri = (dotenv.env["API_URL"] ?? 'localhost') +
        '/api-aggregator/nested-function-infos';
    final headers = await Auth.getHeaders(context, state);
    await initOptions();
    final dio = Dio()..interceptors.add(DioCacheInterceptor(options: _options!));
    final resp = await dio.get<List<dynamic>?>(uri, options: Options(headers: headers));
    if (resp.statusCode == null || resp.statusCode! > 304) {
      throw UnexpectedStatusCodeException(resp.statusCode);
    }
    if (resp.statusCode == 304) {
      _logger.d("Using cached nested functions");
    }

    final l = resp.data ?? [];
    return List<NestedFunction>.generate(
        l.length, (index) => NestedFunction.fromJson(l[index]));
  }
}
