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
import 'package:mobile_app/exceptions/argument_exception.dart';
import 'package:mobile_app/models/device_search_filter.dart';

import '../exceptions/unexpected_status_code_exception.dart';
import '../models/device_instance.dart';
import '../models/network.dart';
import '../shared/keyed_list.dart';
import '../theme.dart';
import '../widgets/shared/toast.dart';
import 'devices.dart';

class MgwDeviceManager {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  static final dio = Dio(BaseOptions(connectTimeout: 1500, sendTimeout: 5000, receiveTimeout: 5000));

  static Future<void> updateDeviceConnectionStatusFromMgw(Iterable<DeviceInstance> devices) async {
    final KeyedList<Network?, DeviceInstance> devicesByNetwork = KeyedList();
    devices.forEach((d) => devicesByNetwork.insert(d.network, d));
    final List<Future> futures = [];
    devicesByNetwork.m.forEach((network, devices) async {
      if (network?.localService != null) {
        futures.add(_updateFromMgw(network!, devices).onError((error, stackTrace) async {
          final deviceIds = devices.map((e) => e.id).toList();
          try {
            await DevicesService.getDevices(devices.length, 0, DeviceSearchFilter("", null, deviceIds), null, forceBackend: true)
                .then((ds) =>
                ds.forEach((d) =>
                devices
                    .firstWhere((d2) => d2.id == d.id)
                    .annotations = d.annotations));
          } catch (e) {
            Toast.showToastNoContext("Device status could not be loaded from network or cloud", MyTheme.errorColor);
          }
        }));
      }
    });
    final start = DateTime.now();
    await Future.wait(futures);
    _logger.d("updateDeviceConnectionStatusFromMgw ${DateTime.now().difference(start)}");
  }

  static Future<void> _updateFromMgw(Network network, Iterable<DeviceInstance> devices) async {
    final service = network.localService;
    if (service == null) {
      throw ArgumentException("localService must not be null");
    }
    String uri = "http://${service.host!}:7002/devices";

    final Response<Map<String, dynamic>> resp;
    try {
      resp = await dio.get<Map<String, dynamic>>(uri);
    } on DioError catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 304) {
        throw UnexpectedStatusCodeException(e.response?.statusCode, "$uri ${e.message}");
      }
      rethrow;
    }

    for (final device in devices) {
      if (resp.data?.containsKey(device.local_id) != true) {
        device.connectionStatus = DeviceConnectionStatus.unknown;
      } else {
        final String status = resp.data![device.local_id]["state"];
        device.connectionStatus = status == "online" ? DeviceConnectionStatus.online : DeviceConnectionStatus.offline;
      }
    }
  }
}
