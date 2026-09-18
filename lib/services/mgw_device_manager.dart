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
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/exceptions/api_unavailable_exception.dart';
import 'package:mobile_app/models/device_search_filter.dart';

import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/exception_log_element.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/keyed_list.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/services/devices.dart';
import 'package:mobile_app/services/mgw/device_manager_new.dart';

class MgwDeviceManager {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  static Future<void> updateDeviceConnectionStatusFromMgw(
      Iterable<DeviceInstance> devices) async {
    final KeyedList<Network?, DeviceInstance> devicesByNetwork = KeyedList();
    devices.forEach((d) => devicesByNetwork.insert(d.network, d));
    final List<Future> futures = [];
    devicesByNetwork.m.forEach((network, devices) async {
      if (network?.localGatewayHosts?.isNotEmpty == true) {
        futures.add(_updateFromMgw(network!, devices)
            .onError((error, stackTrace) async {
          ExceptionLogElement.Log(error.toString());
          if (!Settings.getLocalMode()) {
            final deviceIds = devices.map((e) => e.id).toList();
            try {
              await DevicesService.getDevices(devices.length, 0,
                      DeviceSearchFilter("", null, deviceIds), null,
                      forceBackend: true)
                  .then((ds) => applyCloudStates(devices, ds.devices));
            } on DioException catch (e, s) {
              if (e.error is ApiUnavailableException) {
                ErrorReporter.report(
                    "Device status could not be loaded from network or cloud",
                    e,
                    s);
              }
            } catch (e, s) {
              // This is already the recovery path, and only DioException was
              // caught above - getDevices also throws UnexpectedStatusCode and
              // AuthException, which are neither. Letting one out rejects the
              // future the caller awaits and strands its networks mutex.
              ErrorReporter.report(
                  "Device status could not be loaded from network or cloud", e, s);
            }
          } else {
            ErrorReporter.report(
                "Device status could not be loaded and local mode is enabled");
          }
        }));
      }
    });
    final start = DateTime.now();
    await Future.wait(futures);
    // Unconditional on purpose, although most states are unchanged: a row
    // listens on its own device only, and what it renders also depends on the
    // network binding, which loadNetworks recomputes right before this. On the
    // devices tab nothing else reaches the row, so notifying just the changed
    // states would leave a device stuck on its pre-merge appearance.
    for (final d in devices) {
      d.notifyStateChanged();
    }
    _logger.d(
        "updateDeviceConnectionStatusFromMgw ${DateTime.now().difference(start)}");
  }

  /// Copies the connection state of [source] onto the matching entries of
  /// [target], without announcing it - the loop at the end of
  /// [updateDeviceConnectionStatusFromMgw] announces every path at once.
  ///
  /// A device [target] does not hold is skipped rather than an error: the id
  /// filter answers loosely, and a device can move networks between the list
  /// load and this refresh. Throwing here escapes the error handler this runs
  /// in and leaves the caller's networks mutex locked for good.
  @visibleForTesting
  static void applyCloudStates(
      Iterable<DeviceInstance> target, Iterable<DeviceInstance> source) {
    for (final d in source) {
      final match = target.where((t) => t.id == d.id);
      if (match.isEmpty) continue;
      match.first.connection_state = d.connection_state;
    }
  }

  static Future<void> _updateFromMgw(
      Network network, Iterable<DeviceInstance> devices) async {
    final ip = network.localGatewayHosts?.first;
    if (ip == null) {
      _logger.d("ip not set");
      return;
    }

    final devicesFromMgw = await DeviceManagerNew(ip).getDevices();
    _logger
        .d("MGW-DEVICE-MANAGER: Loaded ${devicesFromMgw.data!.length} devices");
    for (final device in devices) {
      if (devicesFromMgw.data?.containsKey(device.local_id) != true) {
        device.connection_state = DeviceConnectionStatus.unknown;
      } else {
        final String status = devicesFromMgw.data![device.local_id]["state"];
        device.connection_state = status == "online"
            ? DeviceConnectionStatus.online
            : DeviceConnectionStatus.offline;
      }
    }
  }
}
