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
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/services/mgw/core_manager.dart';
import 'package:mobile_app/services/mgw/endpoint.dart';
import 'package:mobile_app/models/mgw_deployment.dart';

const LOG_PREFIX = "MGW-DEVICE-MANAGER-SERVICE";

class DeviceManagerNew {
  MgwCoreService? mgwCoreService;
  MgwEndpointService? mgwEndpointService;

  DeviceManagerNew(MGW gateway) {
    mgwCoreService = MgwCoreService(gateway);
    mgwEndpointService = MgwEndpointService(gateway);
  }

  final _logger = Logger(
    printer: SimplePrinter(),
  );

  static const deviceManagerModuleName =
      "github.com/SENERGY-Platform/device-management-service/mgw-module";

  Future<List<Endpoint>> getDeviceManagerEndpoints() =>
      mgwCoreService!.cachedEndpointsOfModule(deviceManagerModuleName);

  Future<Response<dynamic>> getDevices() async {
    _logger
        .d("$LOG_PREFIX - getDevices: Try to retrieve device manager endpoint");
    var deviceManagerEndpoints = await getDeviceManagerEndpoints();
    if (deviceManagerEndpoints.isEmpty) {
      throw ("$LOG_PREFIX: No endpoints found for device manager");
    }
    _logger.d(
        "$LOG_PREFIX: Load devices from device manager location: ${deviceManagerEndpoints.first.location}/devices");
    try {
      return await mgwEndpointService!.GetFromExposedPath(
          "${deviceManagerEndpoints.first.location}/devices");
    } catch (e) {
      // Drops only this gateway's device-manager endpoints, then asks again.
      await mgwCoreService!.dropCachedEndpoints(deviceManagerModuleName);
      _logger.d(
          "$LOG_PREFIX - getDevices: Try to retrieve device manager endpoint");
      deviceManagerEndpoints = await getDeviceManagerEndpoints();
      if (deviceManagerEndpoints.isEmpty) {
        throw ("$LOG_PREFIX: No endpoints found for device manager");
      }
    }
    return await mgwEndpointService!
        .GetFromExposedPath("${deviceManagerEndpoints.first.location}/devices");
  }
}
