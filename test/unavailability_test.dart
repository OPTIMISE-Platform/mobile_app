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

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/unavailability.dart';

import 'golden_helper.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() async {
    resetAppStateForGolden();
    await Settings.setLocalMode(false);
  });

  /// A network of the device "fan", with a gateway on it when [gateway].
  Network networkOfFan({required bool gateway}) => Network(
      'network-1',
      'Home',
      false,
      ['fan-local'],
      ['fan'],
      DeviceConnectionStatus.online,
      '',
      'owner-1')
    ..localGateways = gateway
        ? [MGW('gw.local', 'gw', '', '10.0.0.2', networkId: 'network-1')]
        : null;

  DeviceInstance fan(DeviceConnectionStatus status) => DeviceInstance(
      'fan',
      'fan-local',
      'Fan',
      null,
      'plug',
      false,
      'owner-1',
      'Fan',
      status);

  test('an offline device is offline, in local mode or not', () async {
    final d = fan(DeviceConnectionStatus.offline);
    expect(deviceUnavailability(d), Unavailability.offline);

    await Settings.setLocalMode(true);
    expect(deviceUnavailability(d), Unavailability.offline,
        reason: 'offline wins over not local');
  });

  test('local mode without a gateway makes an online device not local',
      () async {
    AppState().networks.add(networkOfFan(gateway: false));
    final d = fan(DeviceConnectionStatus.online);

    await Settings.setLocalMode(true);
    expect(deviceUnavailability(d), Unavailability.notLocal);
  });

  test('a device behind a local gateway is available in local mode', () async {
    AppState().networks.add(networkOfFan(gateway: true));
    final d = fan(DeviceConnectionStatus.online);

    await Settings.setLocalMode(true);
    expect(deviceUnavailability(d), isNull);
  });

  test('outside local mode a device without a gateway is available', () {
    final d = fan(DeviceConnectionStatus.online);
    expect(deviceUnavailability(d), isNull);
  });

  test('a group outside a locally served network is not local in local mode',
      () async {
    final group = DeviceGroup('hall', 'Hall', [], '', [], null);

    expect(groupUnavailability(group), isNull);
    await Settings.setLocalMode(true);
    expect(groupUnavailability(group), Unavailability.notLocal);
  });

  test('a group in a network with a gateway is available in local mode',
      () async {
    final group = DeviceGroup('hall', 'Hall', [], '', [], null)
      ..network = networkOfFan(gateway: true);

    await Settings.setLocalMode(true);
    expect(groupUnavailability(group), isNull);
  });
}
