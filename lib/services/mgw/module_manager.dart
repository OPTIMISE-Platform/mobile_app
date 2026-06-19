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
  // Use this service to access the MGW module-manager to manage deployments and modules

  final basePath = "/module-manager";
  MgwApiService mgwApiService = MgwApiService("", true);

  MgwModuleService(String host) {
    this.mgwApiService = MgwApiService(host, true);
  }
  final _logger = Logger(
    printer: SimplePrinter(),
  );

  Future<List<Module>> getModules() async {
    var path = "$basePath/modules";
    _logger.d("$LOG_PREFIX: Load modules from MGW at $path");
    var resp = await mgwApiService.Get(path, Options());
    List<Module> modules = [];
    if(resp.data == null) {
      _logger.e("$LOG_PREFIX: Modules response is null");
      throw("Modules response is null");
    }

    for (final value in resp.data!.values) {
      var module = Module.fromJson(value);
      modules.add(module);
    }
    return modules;
  }

  Future<List<Deployment>> getDeployments(String? modID) async {
    var path = basePath + "/deployments";

    if(modID != null) {
      path += "?module_id=" + modID + "&container_info=true";
    } else {
      path += "?container_info=true";
    }

    _logger.d(LOG_PREFIX + ": MGW-Module-Manager: Load deployments from MGW at " + path);
    var resp = await mgwApiService.Get(path, Options());
    List<Deployment> deployments = [];
    if(resp.data == null) {
      _logger.e(LOG_PREFIX + ": MGW-Module-Manager: Deployments response is null");
      throw("Deployments response is null");
    }
    _logger.d(LOG_PREFIX + ": MGW-Module-Manager: Got deployments: " + resp.data.toString());

    for (final value in resp.data!.values) {
      var deployment = Deployment.fromJson(value);
      deployments.add(deployment);
    }
    return deployments;
  }

  Future<bool> ModuleIsDeployed(String modID) async {
    _logger.d(LOG_PREFIX + ": MGW-Module-Manager: Check if module " + modID + " is deployed");
    var moduleMap = await getDeployments(modID);
    return moduleMap.isEmpty;
  }
}
