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
import 'package:flutter/cupertino.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/models/mgw_deployment.dart';
import 'package:mobile_app/services/mgw/restricted.dart';

import '../../shared/isar.dart';
import 'error.dart';

const LOG_PREFIX = "MGW-ENDPOINT-SERVICE";

class MgwEndpointService {
  // Use this service to access exposed deployment endpoints
  // Session tokens are added automatically

  final _logger = Logger(
    printer: SimplePrinter(),
  );
  MgwService mgwService = MgwService("", true);

  MgwEndpointService(String host) {
    mgwService = MgwService(host, true);
  }

  Future<Response<dynamic>> GetFromExposedPath(String path) async {
    _logger.d("$LOG_PREFIX: Get from exposed deployment path: $path");
    try {
      return await mgwService.Get(path, Options(contentType: Headers.jsonContentType));
    } on Failure {
      rethrow;
    }
  }

  Future<Response<dynamic>> PostToExposedPath(String path, commands) async {
    _logger.d("$LOG_PREFIX: Post to exposed deployment path: $path");
    return await mgwService.Post(path, commands, Options(contentType: Headers.jsonContentType));
  }
}
