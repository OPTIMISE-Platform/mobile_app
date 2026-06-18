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
import 'package:http_cache_hive_store/http_cache_hive_store.dart';import 'package:logger/logger.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/exceptions/unexpected_status_code_exception.dart';
import 'package:mobile_app/models/characteristic.dart';
import 'package:mobile_app/shared/dio_factory.dart';
import 'package:mobile_app/services/api_available.dart';
import 'package:mobile_app/services/auth.dart';

class CharacteristicsService {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  static CacheOptions? _options;

  static String uri =
      '${Settings.getApiUrl() ?? 'localhost'}/device-repository/characteristics';

  static Future<List<Characteristic>> getCharacteristics() async {
    final List<Characteristic> result = [];

    final Map<String, String> queryParameters = {};
    queryParameters["leafsOnly"] = "false";

    final headers = await Auth().getHeaders();
    final dio = await DioFactory.create(DioConfig.standard);
    DioFactory.setHeaders(DioConfig.standard, headers);
    final Response<List<dynamic>?> resp;
    try {
      resp = await dio.get<List<dynamic>?>(uri,
          queryParameters: queryParameters, options: Options(headers: headers));
    } on DioException catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 304) {
        throw UnexpectedStatusCodeException(
            e.response?.statusCode, "$uri ${e.message}");
      }
      rethrow;
    }
    if (resp.statusCode == 304) {
      _logger.d("Using cached characteristics");
    }

    final l = resp.data ?? [];
    result.addAll(List<Characteristic>.generate(
        l.length, (index) => Characteristic.fromJson(l[index])));

    return result;
  }

  static bool isAvailable() => ApiAvailableService().isAvailable(uri);
}
