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
import 'package:mobile_app/models/mgw_module.dart';

import 'package:mobile_app/services/mgw/api.dart';

const LOG_PREFIX = "MGW-MODULE-MANAGER-SERVICE";

class MgwModuleService {
  MgwModuleService._(this.mgwApiService);

  static const basePath = "/module-manager";
  final MgwApiService mgwApiService;
  final _logger = Logger(printer: SimplePrinter());

  static Future<MgwModuleService> create(String host) async {
    final mgwApiService = await MgwApiService.create(host, true);
    return MgwModuleService._(mgwApiService);
  }

  Future<List<Module>> getModules() async {
    const path = "$basePath/modules";
    _logger.d("$LOG_PREFIX: Load modules from MGW at $path");
    final resp = await mgwApiService.Get(path, Options());

    if (resp.data == null) {
      _logger.e("$LOG_PREFIX: Modules response is null");
      throw Exception("Modules response is null");
    }

    return resp.data!.values.map((value) => Module.fromJson(value)).toList();
  }

  Future<List<Deployment>> getDeployments(String? modID) async {
    final query = modID != null
        ? "?module_id=$modID&container_info=true"
        : "?container_info=true";
    final path = "$basePath/deployments$query";

    _logger.d("$LOG_PREFIX: Load deployments from MGW at $path");
    final resp = await mgwApiService.Get(path, Options());

    if (resp.data == null) {
      _logger.e("$LOG_PREFIX: Deployments response is null");
      throw Exception("Deployments response is null");
    }

    _logger.d("$LOG_PREFIX: Got deployments: ${resp.data}");
    return resp.data!.values.map((value) => Deployment.fromJson(value)).toList();
  }

  Future<bool> ModuleIsDeployed(String modID) async {
    _logger.d("$LOG_PREFIX: Check if module $modID is deployed");
    final deployments = await getDeployments(modID);
    return deployments.isNotEmpty; // fixed: was returning isEmpty which was inverted
  }
}
