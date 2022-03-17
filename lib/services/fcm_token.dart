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
import 'package:http/http.dart' as http;


import '../exceptions/unexpected_status_code_exception.dart';
import 'auth.dart';

class FcmTokenService {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  static CacheOptions? _options;
  static late final Dio? _dio;
  static final _client = http.Client();

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

    _dio = Dio()..interceptors.add(DioCacheInterceptor(options: _options!));
  }

  static registerFcmToken(String token) async {
    final url = (dotenv.env["API_URL"] ?? 'localhost') +
        '/notifications-v2/fcm-tokens/' + token;

    var uri = Uri.parse(url);
    if (url.startsWith("https://")) {
      uri = uri.replace(scheme: "https");
    }
    final headers = await Auth.getHeaders(null, null);
    await initOptions();
    final resp = await _dio!.post(url, options: Options(headers: headers));
    if (resp.statusCode == null || resp.statusCode! > 304) {
      throw UnexpectedStatusCodeException(resp.statusCode);
    }

    if (resp.statusCode == 304) {
      _logger.d("Not updating FCM token: Recently updated");
    }
  }

  static deregisterFcmToken(String token) async {
    final url = (dotenv.env["API_URL"] ?? 'localhost') +
        '/notifications-v2/fcm-tokens/' + token;

    var uri = Uri.parse(url);
    if (url.startsWith("https://")) {
      uri = uri.replace(scheme: "https");
    }
    final headers = await Auth.getHeaders(null, null);

    final resp = await _client.delete(uri, headers: headers);
    if (resp.statusCode > 204 && resp.statusCode != 404) { // dont have to delete what cant be found
      throw UnexpectedStatusCodeException(resp.statusCode);
    }
    await initOptions();
    final key = _options!.keyBuilder(RequestOptions(path: url, method: 'POST'));
    await _options?.store?.delete(key); // ensure token is resubmitted when registered again
  }
}

