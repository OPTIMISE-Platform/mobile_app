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
import 'package:mobile_app/models/device_class.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/exceptions/unexpected_status_code_exception.dart';
import 'package:mobile_app/shared/dio_factory.dart';
import 'package:mobile_app/services/api_available.dart';
import 'package:mobile_app/services/auth.dart';

class DeviceClassesService {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  static String uri =
      '${Settings.getApiUrl() ?? 'localhost'}/api-aggregator/device-class-uses';

  static Future<List<DeviceClass>> getDeviceClasses() async {
    final Map<String, String> queryParameters = {};

    final headers = await Auth().getHeaders();
    final dio = await DioFactory.create(DioConfig.cached7);
    final Response<Map<String, dynamic>?> resp;
    try {
      resp = await dio.get<Map<String, dynamic>?>(uri,
          queryParameters: queryParameters, options: Options(headers: headers));
    } on DioException catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 304) {
        throw UnexpectedStatusCodeException(
            e.response?.statusCode, "$uri ${e.message}");
      }
      rethrow;
    }
    if (resp.statusCode == 304) {
      _logger.d("Using cached device classes");
    }
    if (resp.data == null) return [];

    final l = resp.data!["device-classes"];
    if (l == null) return [];
    final deviceClasses = List<DeviceClass>.generate(
        l.length, (index) => DeviceClass.fromJson(l[index]));
    for (var element in deviceClasses) {
      for (var s in (resp.data!["used-devices"][element.id] as List<dynamic>)) {
        element.deviceIds.add(s as String);
      }
    }
    return deviceClasses;
  }

  static bool isAvailable() => ApiAvailableService().isAvailable(uri);
}
