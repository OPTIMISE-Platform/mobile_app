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
import 'package:mobile_app/models/mgw_deployment.dart';
import 'package:mobile_app/services/mgw/api.dart';

const LOG_PREFIX = "MGW-CORE-MANAGER-SERVICE";

class MgwCoreService {
  MgwCoreService._(this.mgwApiService);

  static const basePath = "/core-manager";
  final MgwApiService mgwApiService;

  final _logger = Logger(printer: SimplePrinter());

  static Future<MgwCoreService> create(String host) async {
    final mgwApiService = await MgwApiService.create(host, true);
    return MgwCoreService._(mgwApiService);
  }

  Future<List<Endpoint>> getEndpointsOfModule(String moduleID) async {
    final path = "$basePath/endpoints?labels=mod_id=$moduleID";
    _logger.d("$LOG_PREFIX: Load endpoints from MGW at $path");
    final resp = await mgwApiService.Get(path, Options());

    if (resp.data == null) {
      _logger.e("$LOG_PREFIX: Endpoint response is null");
      throw Exception("Endpoint response is null");
    }

    return resp.data!.values.map((value) {
      final endpoint = Endpoint.fromJson(value);
      endpoint.moduleName = moduleID;
      return endpoint;
    }).toList();
  }
}
