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
import 'package:logger/logger.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/api_available_interceptor.dart';

import 'package:mobile_app/exceptions/unexpected_status_code_exception.dart';
import 'package:mobile_app/shared/http_client_adapter.dart';
import 'package:mobile_app/services/api_available.dart';
import 'package:mobile_app/services/auth.dart';

class FcmTokenService {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  static CacheOptions? _options;
  static late final Dio? _dio;
  static final baseUrl = '${Settings.getApiUrl() ?? 'localhost'}/notifications-v2/fcm-tokens';

  static initOptions() async {
    if (_options != null && _dio != null) {
      return;
    }

    _options = CacheOptions(
      store: HiveCacheStore(await CacheHelper.getCacheFile()),
      policy: CachePolicy.forceCache,
      hitCacheOnErrorExcept: [401, 403],
      maxStale: const Duration(days: 7),
      priority: CachePriority.normal,
      keyBuilder: CacheHelper.bodyCacheIDBuilder,
      allowPostMethod: true,
    );

    _dio = Dio()
      ..interceptors.add(DioCacheInterceptor(options: _options!))
      ..interceptors.add(ApiAvailableInterceptor())
      ..httpClientAdapter = AppHttpClientAdapter();
  }

  static registerFcmToken(String token) async {
    final url = '$baseUrl/$token';

    var uri = Uri.parse(url);
    if (url.startsWith("https://")) {
      uri = uri.replace(scheme: "https");
    }
    final headers = await Auth().getHeaders();
    await initOptions();
    final Response resp;
    try {
      resp = await _dio!.post(url, options: Options(headers: headers));
    } on DioException catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 304) {
        throw UnexpectedStatusCodeException(e.response?.statusCode, "$url ${e.message}");
      }
      rethrow;
    }

    if (resp.statusCode == 304) {
      _logger.d("Not updating FCM token: Recently updated");
    }
  }

  static deregisterFcmToken(String token) async {
    final url = '$baseUrl/$token';

    final headers = await Auth().getHeaders();
    await initOptions();
    final resp = await _dio!.delete(url, options: Options(headers: headers));
    if (resp.statusCode == null || (resp.statusCode! > 204 && resp.statusCode != 404)) {
      // dont have to delete what cant be found
      throw UnexpectedStatusCodeException(resp.statusCode, url);
    }
    await initOptions();
    final key = _options!.keyBuilder(RequestOptions(path: url, method: 'POST'));
    await _options?.store?.delete(key); // ensure token is resubmitted when registered again
  }

  static bool isAvailable() => ApiAvailableService().isAvailable(baseUrl);

}
