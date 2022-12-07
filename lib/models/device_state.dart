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

import 'package:mobile_app/models/device_command.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/service.dart';

import '../services/settings.dart';
import 'content_variable.dart';
import 'device_type.dart';

class DeviceState {
  dynamic value;
  String functionId;
  bool isControlling, transitioning = false;
  String? serviceId, serviceGroupKey, aspectId, groupId, deviceClassId, deviceId, path;

  DeviceInstance? deviceInstance;
  DeviceGroup? deviceGroup;

  DeviceState(this.value, this.serviceId, this.serviceGroupKey, this.functionId, this.aspectId, this.isControlling, this.groupId, this.deviceClassId,
      this.deviceId, this.path);

  DeviceCommand toCommand([dynamic value, DeviceGroup? deviceGroup]) {
    final command = DeviceCommand(
        functionId,
        deviceId,
        serviceId,
        aspectId,
        groupId,
        deviceClassId,
        value,
        Settings.getFunctionPreferredCharacteristicId(functionId));
    command.deviceInstance = deviceInstance;
    command.deviceGroup = deviceGroup ?? this.deviceGroup;
    return command;
  }
}

class StateHelper {
  static final Map<String, List<DeviceState>> _states = {};

  static List<DeviceState> getStates(DeviceType deviceType, DeviceInstance device) {
    if (_states.containsKey(deviceType.id)) {
      // only once
      final states = _states[deviceType.id];
      return List<DeviceState>.generate(states!.length, (i) {
        final state = DeviceState(states[i].value, states[i].serviceId, states[i].serviceGroupKey, states[i].functionId, states[i].aspectId,
            states[i].isControlling, null, null, device.id, states[i].path);
        state.deviceInstance = device;
        return state;
      });
    }
    final List<DeviceState> states = [];
    for (final service in deviceType.services) {
      for (final output in service.outputs ?? []) {
        _addStateFromContentVariable(service, output.content_variable, false, "", states, device);
      }

      for (final input in service.inputs ?? []) {
        _addStateFromContentVariable(service, input.content_variable, true, "", states, device);
      }
    }
    _states[deviceType.id] = states;
    return states;
  }

  static _addStateFromContentVariable(
      Service service, ContentVariable contentVariable, bool isInput, String parentPath, List<DeviceState> states, DeviceInstance device) async {
    final path = parentPath + (parentPath.isEmpty ? "" : ".") + (contentVariable.name ?? "");
    if (contentVariable.function_id != null) {
      final state = DeviceState(
          null, service.id, service.service_group_key, contentVariable.function_id!, contentVariable.aspect_id, isInput, null, null, device.id, path);
      state.deviceInstance = device;
      states.add(state);
    }
    contentVariable.sub_content_variables?.forEach((element) => _addStateFromContentVariable(service, element, isInput, path, states, device));
  }
}
