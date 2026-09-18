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
import 'package:mobile_app/mixins/device_mixin.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/services/mgw_device_manager.dart';

DeviceInstance _device(String id, DeviceConnectionStatus state) =>
    DeviceInstance(id, "local-$id", id, [], "dt", false, "owner", id, state);

void main() {
  group("applyConnectionStates", () {
    test("copies the state onto the matching device", () {
      final target = [_device("a", DeviceConnectionStatus.online)];
      DeviceMixin.applyConnectionStates(
          target, [_device("a", DeviceConnectionStatus.offline)]);
      expect(target.first.connection_state,
          equals(DeviceConnectionStatus.offline));
    });

    test("tells the device it changed", () {
      // The list listens per device, so a state written without this stays
      // invisible until something rebuilds the whole list.
      final target = [_device("a", DeviceConnectionStatus.online)];
      var notified = 0;
      target.first.stateNotifier.addListener(() => notified++);
      DeviceMixin.applyConnectionStates(
          target, [_device("a", DeviceConnectionStatus.offline)]);
      expect(notified, equals(1));
    });

    test("stays quiet when nothing changed", () {
      final target = [_device("a", DeviceConnectionStatus.online)];
      var notified = 0;
      target.first.stateNotifier.addListener(() => notified++);
      DeviceMixin.applyConnectionStates(
          target, [_device("a", DeviceConnectionStatus.online)]);
      expect(notified, equals(0));
    });

    test("ignores a device the target does not hold", () {
      final target = [_device("a", DeviceConnectionStatus.online)];
      DeviceMixin.applyConnectionStates(
          target, [_device("b", DeviceConnectionStatus.offline)]);
      expect(target.first.connection_state,
          equals(DeviceConnectionStatus.online));
    });

    test("updates each device of a mixed answer", () {
      final target = [
        _device("a", DeviceConnectionStatus.online),
        _device("b", DeviceConnectionStatus.online),
      ];
      final notified = <String>[];
      target[0].stateNotifier.addListener(() => notified.add("a"));
      target[1].stateNotifier.addListener(() => notified.add("b"));
      DeviceMixin.applyConnectionStates(target, [
        _device("a", DeviceConnectionStatus.offline),
        _device("b", DeviceConnectionStatus.online),
      ]);
      expect(target[0].connection_state,
          equals(DeviceConnectionStatus.offline));
      expect(target[1].connection_state, equals(DeviceConnectionStatus.online));
      expect(notified, equals(["a"]));
    });
  });

  group("applyCloudStates", () {
    test("skips a device the network list does not hold", () {
      // Throwing here escapes the error handler this runs in, and the caller
      // then never releases its networks mutex - the tab spins until restart.
      final target = [_device("a", DeviceConnectionStatus.online)];
      expect(
          () => MgwDeviceManager.applyCloudStates(
              target, [_device("b", DeviceConnectionStatus.offline)]),
          returnsNormally);
      expect(target.first.connection_state,
          equals(DeviceConnectionStatus.online));
    });

    test("copies the state it does hold", () {
      final target = [
        _device("a", DeviceConnectionStatus.online),
        _device("b", DeviceConnectionStatus.online),
      ];
      MgwDeviceManager.applyCloudStates(target, [
        _device("b", DeviceConnectionStatus.offline),
        _device("c", DeviceConnectionStatus.offline),
      ]);
      expect(target[0].connection_state, equals(DeviceConnectionStatus.online));
      expect(target[1].connection_state,
          equals(DeviceConnectionStatus.offline));
    });

    test("leaves the announcing to the caller", () {
      // Announcing here too would rebuild every changed row twice.
      final target = [_device("a", DeviceConnectionStatus.online)];
      var notified = 0;
      target.first.stateNotifier.addListener(() => notified++);
      MgwDeviceManager.applyCloudStates(
          target, [_device("a", DeviceConnectionStatus.offline)]);
      expect(notified, equals(0));
    });
  });
}
