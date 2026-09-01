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
import 'package:logger/logger.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/exceptions/unexpected_status_code_exception.dart';
import 'package:mobile_app/shared/dio_factory.dart';
import 'package:mobile_app/services/api_available.dart';
import 'package:mobile_app/services/auth.dart';

class FcmTokenService {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  static final baseUrl = '${Settings.getApiUrl() ?? 'localhost'}/notifications-v2/fcm-tokens';

  static registerFcmToken(String token) async {
    final url = '$baseUrl/$token';

    var uri = Uri.parse(url);
    if (url.startsWith("https://")) {
      uri = uri.replace(scheme: "https");
    }
    final headers = await Auth().getHeaders();
    final Response resp;
    try {
      // Uncached: this used to run on a POST-caching dio to throttle repeat
      // registrations, but the cached entry outlived a deregistration, so
      // registering again after a logout was answered from the cache and never
      // reached the backend — push notifications stayed dead until the entry
      // aged out. The endpoint carries the token in its path and upserts.
      final dio = await DioFactory.create(DioConfig.standard);
      resp = await dio.post(url, options: Options(headers: headers));
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
    final dio = await DioFactory.create(DioConfig.standard);
    final resp = await dio.delete(url, options: Options(headers: headers));
    if (resp.statusCode == null || (resp.statusCode! > 204 && resp.statusCode != 404)) {
      // dont have to delete what cant be found
      throw UnexpectedStatusCodeException(resp.statusCode, url);
    }
  }

  static bool isAvailable() => ApiAvailableService().isAvailable(baseUrl);

}
