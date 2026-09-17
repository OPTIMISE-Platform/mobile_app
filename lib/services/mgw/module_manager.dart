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
import 'package:mobile_app/models/mgw_module.dart';

import 'package:mobile_app/services/mgw/api.dart';

const LOG_PREFIX = "MGW-MODULE-MANAGER-SERVICE";

class MgwModuleService {
  // Use this service to access the MGW module-manager to manage deployments and modules

  final basePath = "/module-manager";
  MgwApiService mgwApiService = MgwApiService("", true);

  MgwModuleService(String host) {
    mgwApiService = MgwApiService(host, true);
  }
  final _logger = Logger(
    printer: SimplePrinter(),
  );

  /// Installed modules, each with its deployment nested.
  ///
  /// There is no deployments collection to read instead: the module-manager
  /// answers `GET /deployments` with 404 and reports a deployment only as part
  /// of its module.
  Future<List<Module>> getModules() async {
    var path = "$basePath/modules-reduced";
    _logger.d("$LOG_PREFIX: Load modules from MGW at $path");
    var resp = await mgwApiService.Get(path, Options());
    final body = resp.data;
    // Not a cast: a gateway that answers with an error envelope or a proxy page
    // would otherwise escape as a raw TypeError, which no caller handles.
    if (body is! List) {
      _logger.e("$LOG_PREFIX: Modules response is not a list: $body");
      throw ("Modules response is not a list");
    }

    List<Module> modules = [];
    for (final value in body) {
      modules.add(Module.fromJson(value));
    }
    // The endpoint returns the modules in a different order between calls, so a
    // list rendered as received swaps rows on its own on every refresh.
    modules.sort((a, b) => a.id.compareTo(b.id));
    return modules;
  }
}
