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
import 'package:mobile_app/models/annotations.dart';
import 'package:mobile_app/models/attribute.dart';
import 'package:mobile_app/models/content_variable.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/models/service.dart';

import '../exceptions/argument_exception.dart';
import 'device_command.dart';

part 'device_instance.g.dart';

enum DeviceConnectionStatus {
  online,
  offline,
  unknown,
}

const attributeFavorite = appOrigin + "/" + "favorite";

@JsonSerializable()
class DeviceInstance {
  String id, local_id, name, device_type_id, creator;
  List<Attribute>? attributes;
  Annotations? annotations;
  bool shared;

  @JsonKey(ignore: true)
  final List<DeviceState> states = [];

  DeviceInstance(this.id, this.local_id, this.name, this.attributes,
      this.device_type_id, this.annotations, this.shared, this.creator);


  factory DeviceInstance.fromJson(Map<String, dynamic> json) =>
      _$DeviceInstanceFromJson(json);

  Map<String, dynamic> toJson() => _$DeviceInstanceToJson(this);

  prepareStates(DeviceType deviceType) {
    if (states.isNotEmpty) { // only once
      return;
    }
    if (deviceType.id != device_type_id) {
      throw ArgumentException("device type has wrong id");
    }
    for (final service in deviceType.services) {
      for (final output in service.outputs ?? []) {
        _addStateFromContentVariable(
          service, output.content_variable, false);
      }

      for (final input in service.inputs ?? []) {
        _addStateFromContentVariable(service, input.content_variable, true);
      }
    }
  }

  List<CommandCallback> getStateFillFunctions([List<String>? limitToFunctionIds]) {
    final List<CommandCallback> result = [];
    for (var i = 0; i < states.length; i++) {
      if (limitToFunctionIds != null && !limitToFunctionIds.contains(states[i].functionId)) {
        continue;
      }
      if (states[i].isControlling) {
        continue;
      }
      result.add(CommandCallback(states[i].toCommand(), (value) {
        if (value is List && value.length == 1) {
          states[i].value = value[0];
        } else {
          states[i].value = value;
        }
        states[i].transitioning = false;
      }));
    }
    return result;
  }

  bool get favorite {
    final i = attributes?.indexWhere((element) => element.key == attributeFavorite && element.origin == appOrigin);
    return i != null && i != -1;
  }

  setFavorite(bool val) {
    if (val) {
      attributes ??= [];
      attributes!.add(Attribute(attributeFavorite, "true", appOrigin));
    } else {
      final i = attributes?.indexWhere((element) => element.key == attributeFavorite);
      if (i != null && i != -1) {
        attributes!.removeAt(i);
      }
    }
  }

  toggleFavorite() {
    setFavorite(!favorite);
  }

  DeviceConnectionStatus getConnectionStatus() {
    if (annotations == null) {
      return DeviceConnectionStatus.unknown;
    }
    if (annotations!.connected) {
      return DeviceConnectionStatus.online;
    } else {
      return DeviceConnectionStatus.offline;
    }
  }

  _addStateFromContentVariable(
      Service service, ContentVariable contentVariable, bool isInput) async {
    if (contentVariable.function_id != null) {
      states.add(DeviceState(null, service.id, service.service_group_key, contentVariable.function_id!,
          contentVariable.aspect_id, isInput, null, null, id));
    }
    contentVariable.sub_content_variables?.forEach(
        (element) => _addStateFromContentVariable(service, element, isInput));
  }
}

class CommandCallback {
  DeviceCommand command;
  Function(dynamic value) callback;
  CommandCallback(this.command, this.callback);
}
