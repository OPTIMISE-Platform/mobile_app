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

import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/services/settings.dart';

/// Why a device cannot be switched right now, the two cases the device list
/// tells apart.
enum Unavailability { offline, notLocal }

/// Why [device] cannot be reached right now, or null when it can.
Unavailability? deviceUnavailability(DeviceInstance device) {
  if (device.connection_state == DeviceConnectionStatus.offline) {
    return Unavailability.offline;
  }
  if (device.network?.localGateways?.isNotEmpty != true &&
      Settings.getLocalMode()) {
    return Unavailability.notLocal;
  }
  return null;
}

/// Why [group] cannot be switched right now, or null when it can. A group
/// outside a locally served network in local mode is not asked for, since the
/// platform will not be asked for it. A group has no connection state of its
/// own, so it is never offline.
Unavailability? groupUnavailability(DeviceGroup group) =>
    Settings.getLocalMode() && group.network?.localGateways?.isNotEmpty != true
        ? Unavailability.notLocal
        : null;
