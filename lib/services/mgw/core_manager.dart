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
  // Use this service to access the MGW core-manager to manage exposed endpoints

  final basePath = "/core-manager";
  MgwApiService mgwApiService = MgwApiService("", true);

  MgwCoreService(String host) {
    mgwApiService = MgwApiService(host, true);
  }
  final _logger = Logger(
    printer: SimplePrinter(),
  );

  Future<List<Endpoint>> getEndpointsOfModule(String moduleID) async {
    var path = "$basePath/endpoints?labels=mod_id=$moduleID";
    _logger.d("$LOG_PREFIX: Load endpoints from MGW at $path");
    var resp = await mgwApiService.Get(path, Options());
    List<Endpoint> endpoints = [];
    if(resp.data == null) {
      _logger.e("$LOG_PREFIX: Endpoint response is null");
      throw("Endpoint response is null");
    }

    for (final value in resp.data!.values) {
      var endpoint = Endpoint.fromJson(value);
      endpoint.moduleName = moduleID;
      endpoints.add(endpoint);
    }
    return endpoints;
  }
}
