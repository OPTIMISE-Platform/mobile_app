/*
 * Copyright 2023 InfAI (CC SES)
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

import '../exceptions/api_unavailable_exception.dart';
import '../services/api_available.dart';

class ApiAvailableInterceptor extends Interceptor {
  static final _instance = ApiAvailableInterceptor._internal();

  factory ApiAvailableInterceptor() => _instance;

  ApiAvailableInterceptor._internal() {}


  @override
  void onRequest(
      RequestOptions options,
      RequestInterceptorHandler handler,
      ) {
    if (!ApiAvailableService().isAvailable(options.path)) {
      handler.reject(DioError(requestOptions: options, type: DioErrorType.other, error: ApiUnavailableException()), true);
    } else {
      handler.next(options);
    }
  }
}
