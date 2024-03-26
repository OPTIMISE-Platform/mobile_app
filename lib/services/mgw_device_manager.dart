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
import 'package:mobile_app/exceptions/api_unavailable_exception.dart';
import 'package:mobile_app/models/device_search_filter.dart';

import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/shared/keyed_list.dart';
import 'package:mobile_app/widgets/shared/toast.dart';
import 'package:mobile_app/services/devices.dart';
import 'package:mobile_app/services/device_manager_old.dart';
import 'package:mobile_app/services/mgw/device_manager_new.dart';
import 'package:mobile_app/services/mgw/error.dart';

class MgwDeviceManager {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  static var useNewDeviceManager = false;

  static Future<void> updateDeviceConnectionStatusFromMgw(
      Iterable<DeviceInstance> devices) async {
    final KeyedList<Network?, DeviceInstance> devicesByNetwork = KeyedList();
    devices.forEach((d) => devicesByNetwork.insert(d.network, d));
    final List<Future> futures = [];
    devicesByNetwork.m.forEach((network, devices) async {
      if (network?.localService != null) {
        futures.add(_updateFromMgw(network!, devices)
            .onError((error, stackTrace) async {
          _logger.e(error);
          final deviceIds = devices.map((e) => e.id).toList();
          try {
            await DevicesService.getDevices(devices.length, 0,
                    DeviceSearchFilter("", null, deviceIds), null,
                    forceBackend: true)
                .then((ds) => ds.forEach((d) => devices
                    .firstWhere((d2) => d2.id == d.id)
                    .annotations = d.annotations));
          } on DioError catch (e) {
            if (e.error! is ApiUnavailableException) {
              Toast.showToastNoContext(
                  "Device status could not be loaded from network or cloud");
            }
          }
        }));
      }
    });
    final start = DateTime.now();
    await Future.wait(futures);
    _logger.d(
        "updateDeviceConnectionStatusFromMgw ${DateTime.now().difference(start)}");
  }

  static Future<void> _setupDeviceManager(String host) async {
    // TODO: remove this check when the old port based deployment of device manager is not running anymore
    _logger.d(
        "MGW-DEVICE-MANAGER: Find out which device manager to use by checking endpoints");
    var deviceManagerEndpoints = [];
    try {
      deviceManagerEndpoints =
          await DeviceManagerNew(host).getDeviceManagerEndpoints();
    } on Failure catch (e) {
      _logger.e("Cant check device manager endpoints: " + e.detailedMessage);
      return;
    } catch (e) {
      _logger.e("Cant check device manager endpoints: " + e.toString());
      return;
    }

    if (deviceManagerEndpoints.isEmpty) {
      useNewDeviceManager = false;
      _logger.d(
          "No endpoints found for device manager -> use port based device manager");
      return;
    }
    _logger.d(
        "Endpoints found for device manager -> use new path based device manager");
    useNewDeviceManager = true;
  }

  static Future<void> _updateFromMgw(
      Network network, Iterable<DeviceInstance> devices) async {
    final service = network.localService;
    var ip = service?.addresses?[0].address;
    if (ip == null) {
      _logger.d("ip not set");
      return;
    }

    await _setupDeviceManager(ip);
    Response<dynamic> devicesFromMgw;
    _logger.d(
        "MGW-DEVICE-MANAGER: Load devices from new device manager: $useNewDeviceManager");
    // TODO remove this part when port based device manager are not used anymore in the future
    if (useNewDeviceManager) {
      devicesFromMgw = await DeviceManagerNew(ip).getDevices();
    } else {
      try {
        devicesFromMgw = await DeviceManagerOld(ip).getDevices();
      } catch (e) {
        rethrow;
      }
    }
    _logger.d("MGW-DEVICE-MANAGER: Loaded devices: $devicesFromMgw");
    for (final device in devices) {
      if (devicesFromMgw.data?.containsKey(device.local_id) != true) {
        device.connectionStatus = DeviceConnectionStatus.unknown;
      } else {
        final String status = devicesFromMgw.data![device.local_id]["state"];
        device.connectionStatus = status == "online"
            ? DeviceConnectionStatus.online
            : DeviceConnectionStatus.offline;
      }
    }
  }
}
