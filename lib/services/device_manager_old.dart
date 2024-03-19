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
import 'package:mobile_app/exceptions/argument_exception.dart';
import 'package:mobile_app/exceptions/api_unavailable_exception.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/shared/api_available_interceptor.dart';

import 'package:mobile_app/exceptions/unexpected_status_code_exception.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/shared/keyed_list.dart';
import 'package:mobile_app/widgets/shared/toast.dart';
import 'package:mobile_app/services/devices.dart';

const LOG_PREFIX = "MGW-OLD-DEVICE-MANAGER-SERVICE";

class DeviceManagerOld {
  var basePath = "";

  DeviceManagerOld(String host) {
    this.basePath = "http://" + host  + ":7002";
  }

  final _logger = Logger(
    printer: SimplePrinter(),
  );

  final dio = Dio(BaseOptions(
      connectTimeout: 1500, sendTimeout: 5000, receiveTimeout: 5000))
    ..interceptors.add(ApiAvailableInterceptor());


  Future<Response<Map<String, dynamic>>> getDevices() async {
    final devicesUrl = basePath + "/devices";
    final Response<Map<String, dynamic>> resp;
    try {
      _logger.d(LOG_PREFIX + ": Try to load devices from: " + devicesUrl);
      resp = await dio.get<Map<String, dynamic>>(devicesUrl);
      return resp;
    } on DioError catch (e) {
      _logger.d(LOG_PREFIX + ": Could not load devices: " + e.message);
      if (e.response?.statusCode == null || e.response!.statusCode! > 304) {
        throw UnexpectedStatusCodeException(e.response?.statusCode, "$devicesUrl ${e.message}");
      }
      rethrow;
    }
  }
}
