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
import 'package:mobile_app/models/service.dart';

import 'content_variable.dart';
import 'device_type.dart';

class DeviceState {
  dynamic value;
  String functionId;
  bool isControlling, transitioning = false;
  String? serviceId, serviceGroupKey, aspectId, groupId, deviceClassId, deviceId, path;

  DeviceState(this.value, this.serviceId, this.serviceGroupKey, this.functionId, this.aspectId, this.isControlling, this.groupId, this.deviceClassId, this.deviceId, this.path);

  DeviceCommand toCommand([dynamic value]) {
    return DeviceCommand(functionId, deviceId, serviceId, aspectId, groupId, deviceClassId, value);
  }
}

class StateHelper {
  static final Map<String, List<DeviceState>> _states = {};

  static List<DeviceState> getStates(DeviceType deviceType, String deviceId) {
    if (_states.containsKey(deviceType.id)) { // only once
      final states = _states[deviceType.id];
      return List<DeviceState>.generate(states!.length, (i) => DeviceState(states[i].value, states[i].serviceId, states[i].serviceGroupKey,
          states[i].functionId, states[i].aspectId, states[i].isControlling, null, null, deviceId, states[i].path));
    }
    final List<DeviceState> states = [];
    for (final service in deviceType.services) {
      for (final output in service.outputs ?? []) {
        _addStateFromContentVariable(
            service, output.content_variable, false, "", states, deviceId);
      }

      for (final input in service.inputs ?? []) {
        _addStateFromContentVariable(service, input.content_variable, true, "", states, deviceId);
      }
    }
    _states[deviceType.id] = states;
    return states;
  }

  static _addStateFromContentVariable(
      Service service, ContentVariable contentVariable, bool isInput, String parentPath, List<DeviceState> states, String deviceId) async {
    final path = parentPath + (parentPath.isEmpty ? "" : ".") + (contentVariable.name ?? "");
    if (contentVariable.function_id != null) {
      states.add(DeviceState(null, service.id, service.service_group_key, contentVariable.function_id!,
          contentVariable.aspect_id, isInput, null, null, deviceId, path));
    }
    contentVariable.sub_content_variables?.forEach(
            (element) => _addStateFromContentVariable(service, element, isInput, path, states, deviceId));
  }
}
