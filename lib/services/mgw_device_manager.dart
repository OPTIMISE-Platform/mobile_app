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
import 'package:mobile_app/exceptions/argument_exception.dart';

import '../exceptions/unexpected_status_code_exception.dart';
import '../models/device_instance.dart';
import '../models/network.dart';
import '../shared/keyed_list.dart';

class MgwDeviceManager {
  static final dio = Dio(BaseOptions(connectTimeout: 1500, sendTimeout: 5000, receiveTimeout: 5000));

  static Future<void> updateDeviceConnectionStatusFromMgw(Iterable<DeviceInstance> devices) async {
    final KeyedList<Network?, DeviceInstance> devicesByNetwork = KeyedList();
    devices.forEach((d) => devicesByNetwork.insert(d.network, d));
    final List<Future> futures = [];
    devicesByNetwork.m.forEach((network, devices) {
      if (network?.localService != null) {
        futures.add(_updateFromMgw(network!, devices));
      }
    });
    await Future.wait(futures);
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
        throw UnexpectedStatusCodeException(e.response?.statusCode);
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
