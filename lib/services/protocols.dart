/*
 * Copyright 2026 InfAI (CC SES)
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
import 'package:mobile_app/models/protocol.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/dio_factory.dart';
import 'package:mobile_app/shared/dio_status.dart';

class ProtocolsService {
  static String uri = '${Settings.getApiUrl() ?? 'localhost'}/device-repository/protocols';

  /// Cached like [DeviceTypesService.getDeviceType]: the Hive HTTP cache, a
  /// protocol definition changes rarely and the body is small.
  static Future<Protocol?> getProtocol(String id) async {
    final url = '$uri/$id';

    final headers = await Auth().getHeaders();
    final dio = await DioFactory.create(DioConfig.cached7);
    final Response<Map<String, dynamic>> resp;
    try {
      resp = await dio.get<Map<String, dynamic>>(url, options: Options(headers: headers));
    } on DioException catch (e) {
      checkReadStatus(e, url);
      rethrow;
    }

    if (resp.data == null || (resp.data is String && (resp.data as String) == "null")) {
      return null;
    }

    return Protocol.fromJson(resp.data!);
  }
}
