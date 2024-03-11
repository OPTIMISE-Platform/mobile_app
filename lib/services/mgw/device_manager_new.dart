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
import 'package:mobile_app/services/mgw/core_manager.dart';
import 'package:mobile_app/services/mgw/endpoint.dart';
import 'package:mobile_app/models/mgw_deployment.dart';

const LOG_PREFIX = "MGW-DEVICE-MANAGER-SERVICE";

class DeviceManagerNew {
  var mgwCoreService;
  var mgwEndpointService;

  DeviceManagerNew(String host) {
    this.mgwCoreService = MgwCoreService(host);
    this.mgwEndpointService = MgwEndpointService(host);
  }

  final _logger = Logger(
    printer: SimplePrinter(),
  );

  Future<List<Endpoint>> getDeviceManagerEndpoints() async {
    return await mgwCoreService.getEndpointsOfModule("github.com/SENERGY-Platform/device-management-service/mgw-module");
  }

  Future<Response<dynamic>> getDevices() async {
    _logger.d(LOG_PREFIX +": Try to retrieve device manager endpoint");
    var deviceManagerEndpoints = await getDeviceManagerEndpoints();
    if(deviceManagerEndpoints.isEmpty) {
      throw(LOG_PREFIX + ": No endpoints found for device manager");
    }
    var exposedPath = deviceManagerEndpoints.first.location;
    _logger.d(LOG_PREFIX+ ": Device Manager is exposed at: " + exposedPath);
    var path = exposedPath + "/devices";

    _logger.d(LOG_PREFIX + ": Load devices from device manager");
    final Response<dynamic> resp = await mgwEndpointService.GetFromExposedPath(path);
    return resp;
  }
}
