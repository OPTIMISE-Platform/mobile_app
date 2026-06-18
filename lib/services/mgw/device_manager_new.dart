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
import 'package:isar_community/isar.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/services/mgw/core_manager.dart';
import 'package:mobile_app/services/mgw/endpoint.dart';
import 'package:mobile_app/models/mgw_deployment.dart';

import '../../shared/isar.dart';

const LOG_PREFIX = "MGW-DEVICE-MANAGER-SERVICE";

class DeviceManagerNew {
  DeviceManagerNew._(this.mgwCoreService, this.mgwEndpointService);

  final MgwCoreService mgwCoreService;
  final MgwEndpointService mgwEndpointService;

  final _logger = Logger(printer: SimplePrinter());

  static Future<DeviceManagerNew> create(String host) async {
    final mgwCoreService = await MgwCoreService.create(host);
    final mgwEndpointService = await MgwEndpointService.create(host);
    return DeviceManagerNew._(mgwCoreService, mgwEndpointService);
  }

  Future<List<Endpoint>> getDeviceManagerEndpoints() async {
    const deviceManagerModuleName =
        "github.com/SENERGY-Platform/device-management-service/mgw-module";

    if (isar != null) {
      final cached = await isar!.endpoints
          .where()
          .moduleNameEqualTo(deviceManagerModuleName)
          .findAll();
      if (cached.isNotEmpty) return cached;
    }

    final endpoints = await mgwCoreService.getEndpointsOfModule(deviceManagerModuleName);

    if (isar != null) {
      await isar!.writeTxn(() async {
        await isar!.endpoints.putAll(endpoints);
      });
    }

    return endpoints;
  }

  Future<Response<dynamic>> getDevices() async {
    _logger.d("$LOG_PREFIX - getDevices: Try to retrieve device manager endpoint");

    Future<List<Endpoint>> getEndpoints() async {
      final endpoints = await getDeviceManagerEndpoints();
      if (endpoints.isEmpty) throw "$LOG_PREFIX: No endpoints found for device manager";
      return endpoints;
    }

    var endpoints = await getEndpoints();
    _logger.d("$LOG_PREFIX: Load devices from ${endpoints.first.location}/devices");

    try {
      return await mgwEndpointService.GetFromExposedPath("${endpoints.first.location}/devices");
    } catch (e) {
      _logger.d("$LOG_PREFIX - getDevices: Clearing cache and retrying");
      await isar!.writeTxn(() async {
        await isar!.endpoints.clear();
      });

      endpoints = await getEndpoints();
      return await mgwEndpointService.GetFromExposedPath("${endpoints.first.location}/devices");
    }
  }
}
