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

import "package:flutter_test/flutter_test.dart";
import "package:mobile_app/models/content.dart";
import "package:mobile_app/models/content_variable.dart";
import "package:mobile_app/models/device_instance.dart";
import "package:mobile_app/models/device_state.dart";
import "package:mobile_app/models/device_type.dart";
import "package:mobile_app/models/service.dart";

DeviceInstance _device(String id) => DeviceInstance(
    id, "local-$id", "name-$id", null, "dt-1", false, "owner", "display-$id", DeviceConnectionStatus.unknown);

DeviceType _deviceType() {
  final contentVariable = ContentVariable(
      "cv-1", "value", null, null, "aspect-1", "function-1", "https://schema.org/Float", null, null, null);
  final output = Content("content-1", "json", "segment-1", contentVariable);
  final service =
      Service("service-1", "local-service-1", "Service 1", "", "protocol-1", "event", "group-1", null, [output]);
  return DeviceType("dt-1", "Type 1", "", "class-1", [service], null);
}

void main() {
  // The template cache in StateHelper is per device-type-id and process-wide.
  // These tests share one type id on purpose: the second call is the cache-hit
  // path under test.
  group("StateHelper.getStates", () {
    test("two devices of the same type get independent states", () {
      final deviceA = _device("device-a");
      final deviceB = _device("device-b");
      final type = _deviceType();

      final statesA = StateHelper.getStates(type, deviceA);
      expect(statesA, hasLength(1));
      // Simulate the live value fill that prepareStates/loadStates performs.
      statesA[0].value = 42;

      final statesB = StateHelper.getStates(type, deviceB);
      expect(statesB, hasLength(1));
      expect(statesB[0].value, isNull,
          reason: "device B must not inherit device A's live value");
      expect(statesB[0].deviceId, deviceB.id);
      expect(statesB[0].deviceInstance, same(deviceB));
      // And A's binding stays intact.
      expect(statesA[0].deviceId, deviceA.id);
      expect(statesA[0].deviceInstance, same(deviceA));
    });

    test("repeated calls for one device never alias each other", () {
      final device = _device("device-c");
      final type = _deviceType();

      final first = StateHelper.getStates(type, device);
      first[0].value = "on";
      final second = StateHelper.getStates(type, device);

      expect(identical(first[0], second[0]), isFalse);
      expect(second[0].value, isNull);
    });
  });
}
