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

import 'package:json_annotation/json_annotation.dart';
import 'package:mobile_app/models/device_command.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/service.dart';
import 'package:mobile_app/models/service_group.dart';

import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/models/content_variable.dart';
import 'package:mobile_app/models/device_type.dart';

part 'device_state.g.dart';

@JsonSerializable()
class DeviceState {
  dynamic value;
  String functionId;
  bool isControlling, transitioning = false;

  @JsonKey(ignore: true)
  DeviceInstance? _deviceInstance;
  @JsonKey(ignore: true)
  DeviceGroup? _deviceGroup;

  DeviceInstance? get deviceInstance {
    return _deviceInstance;
  }

  set deviceInstance(DeviceInstance? instance) {
    _deviceInstance = instance;
    name = deviceInstance?.display_name;
  }

  DeviceGroup? get deviceGroup {
    return _deviceGroup;
  }

  set deviceGroup(DeviceGroup? instance) {
    _deviceGroup = instance;
    name = deviceGroup?.name;
  }

  String? serviceId, serviceGroupKey, aspectId, groupId, deviceClassId, deviceId, path, name, serviceGroupName;

  DeviceState(this.value, this.serviceId, this.serviceGroupKey, this.functionId, this.aspectId, this.isControlling, this.groupId, this.deviceClassId,
      this.deviceId, this.path, this.serviceGroupName) {
    name = deviceInstance?.display_name ?? deviceGroup?.name;
  }

  factory DeviceState.fromJson(Map<String, dynamic> json) => _$DeviceStateFromJson(json);

  Map<String, dynamic> toJson() => _$DeviceStateToJson(this);

  DeviceCommand toCommand([dynamic value, DeviceGroup? deviceGroup]) {
    final command = DeviceCommand(
        functionId, deviceId, serviceId, aspectId, groupId, deviceClassId, value, Settings.getFunctionPreferredCharacteristicId(functionId));
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
            states[i].isControlling, null, null, device.id, states[i].path, states[i].serviceGroupName);
        state.deviceInstance = device;
        return state;
      });
    }
    final List<DeviceState> states = [];
    for (final service in deviceType.services) {
      final serviceGroupName =
          deviceType.service_groups?.firstWhere((e) => e.key == service.service_group_key, orElse: () => ServiceGroup("", "", "")).name;
      for (final output in service.outputs ?? []) {
        _addStateFromContentVariable(service, output.content_variable, false, "", states, device, serviceGroupName);
      }

      for (final input in service.inputs ?? []) {
        _addStateFromContentVariable(service, input.content_variable, true, "", states, device, serviceGroupName);
      }
    }
    _states[deviceType.id] = states;
    return states;
  }

  static _addStateFromContentVariable(Service service, ContentVariable contentVariable, bool isInput, String parentPath, List<DeviceState> states,
      DeviceInstance device, String? serviceGroupName) async {
    final path = parentPath + (parentPath.isEmpty ? "" : ".") + (contentVariable.name ?? "");
    if (contentVariable.function_id != null) {
      final state = DeviceState(null, service.id, service.service_group_key, contentVariable.function_id!, contentVariable.aspect_id, isInput, null,
          null, device.id, path, serviceGroupName);
      state.deviceInstance = device;
      final idx = states.indexWhere((element) => element.serviceGroupKey == service.service_group_key
          && element.functionId == contentVariable.function_id!
          && element.aspectId == contentVariable.aspect_id
          && element.isControlling == isInput);
      if (idx == -1) {
        states.add(state);
      }
    }
    contentVariable.sub_content_variables
        ?.forEach((element) => _addStateFromContentVariable(service, element, isInput, path, states, device, serviceGroupName));
  }
}
