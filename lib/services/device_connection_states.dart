/*
 * Copyright 2026 InfAI (CC SES)
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

import 'dart:math';

import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/services/devices.dart';
import 'package:mobile_app/services/mgw_device_manager.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/error_reporter.dart';

/// Brings the connection state of [devices] up to date the way the device
/// list does: from the paired gateway for a device in a network that has one,
/// from the platform, bypassing the device cache, for every other device.
/// [platformStatesFresh] skips the platform request for devices that were
/// just fetched from it.
///
/// A device whose state changed is notified. When the platform cannot be
/// asked, the cached state is stale and becomes unknown, as in the device
/// list. Never throws.
Future<void> refreshDeviceConnectionStates(
  List<DeviceInstance> devices, {
  bool platformStatesFresh = false,
}) async {
  if (devices.isEmpty) return;
  final outsideLocalNet = platformStatesFresh
      ? const <DeviceInstance>[]
      : devices
            .where((d) => d.network?.localGateways?.isNotEmpty != true)
            .toList(growable: false);
  await Future.wait([
    MgwDeviceManager.updateDeviceConnectionStatusFromMgw(devices).catchError((
      Object e,
      StackTrace s,
    ) {
      ErrorReporter.log('Could not refresh the gateway device status', e, s);
    }),
    for (var i = 0; i < outsideLocalNet.length; i += _chunk)
      _refreshFromPlatform(
        outsideLocalNet.sublist(i, min(i + _chunk, outsideLocalNet.length)),
      ),
  ]);
}

/// Ids per platform request, as [DevicesService.getDevicesByIds] sends them.
const _chunk = 50;

Future<void> _refreshFromPlatform(List<DeviceInstance> devices) async {
  final ids = devices.map((d) => d.id).toList(growable: false);
  final List<DeviceInstance> fresh;
  try {
    fresh = (await DevicesService.getDevices(
      ids.length,
      0,
      DeviceSearchFilter('', deviceIds: ids),
      null,
      forceBackend: true,
    )).devices;
  } catch (e, s) {
    if (!Settings.getLocalMode()) {
      ErrorReporter.report('Error refreshing device status', e, s);
    }
    for (final device in devices) {
      _apply(device, DeviceConnectionStatus.unknown);
    }
    return;
  }
  for (final d in fresh) {
    // The id filter answers loosely, so a device not asked for is skipped.
    final match = devices.where((t) => t.id == d.id);
    if (match.isEmpty) continue;
    _apply(match.first, d.connection_state);
  }
}

void _apply(DeviceInstance device, DeviceConnectionStatus status) {
  if (device.connection_state == status) return;
  device.connection_state = status;
  device.notifyStateChanged();
}
