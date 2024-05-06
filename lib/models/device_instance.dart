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

import 'package:isar/isar.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/annotations.dart';
import 'package:mobile_app/models/attribute.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/models/device_type.dart';

import 'package:mobile_app/exceptions/argument_exception.dart';
import 'package:mobile_app/native_pipe.dart';
import 'package:mobile_app/shared/isar.dart';
import 'package:mobile_app/models/device_command.dart';
import 'package:mobile_app/models/network.dart';

part 'device_instance.g.dart';

enum DeviceConnectionStatus {
  online,
  offline,
  unknown,
}

const attributeFavorite = "$appOrigin/favorite";
const attributeNickname = "$sharedOrigin/nickname";

@JsonSerializable()
@collection
class DeviceInstance {
  @Index(type: IndexType.hash)
  String id, local_id;
  String name, device_type_id, creator;

  @Index(caseSensitive: false)
  String? display_name;
  List<Attribute>? attributes;
  Annotations? annotations;
  bool shared;

  @JsonKey(ignore: true)
  Id isarId = -1;

  @JsonKey(ignore: true)
  @ignore
  final List<DeviceState> states = [];

  @JsonKey(ignore: true)
  @ignore
  Network? network;

  DeviceInstance(
      this.id, this.local_id, this.name, this.attributes, this.device_type_id, this.annotations, this.shared, this.creator, this.display_name) {
    isarId = fastHash(id);
    final networkIndex = AppState().networks.indexWhere((n) => n.device_local_ids?.contains(local_id) ?? false);
    if (networkIndex != -1) network = AppState().networks[networkIndex];
  }

  factory DeviceInstance.fromJson(Map<String, dynamic> json) => _$DeviceInstanceFromJson(json);

  Map<String, dynamic> toJson() => _$DeviceInstanceToJson(this);

  prepareStates(DeviceType deviceType) {
    if (states.isNotEmpty) {
      // only once
      return;
    }
    if (deviceType.id != device_type_id) {
      throw ArgumentException("device type has wrong id");
    }
    states.addAll(StateHelper.getStates(deviceType, this));
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
      states[i].transitioning = true;
      result.add(CommandCallback(states[i].toCommand(), (value) {
        if (value is List && value.length == 1) {
          states[i].value = value[0];
        } else {
          states[i].value = value;
        }
        states[i].transitioning = false;
        NativePipe.handleDeviceStateUpdate(states[i]);
      }));
    }
    return result;
  }

  Future<bool> isFavorite() async {
    final device =
    await isar!.deviceInstances.where().idEqualTo(id).findFirst();
    return device?.favorite ?? false;
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @Index()
  bool favorite = false;

  setFavorite(bool val) {
    if (val) {
      attributes ??= [];
      attributes = attributes!.toList(); // ensure growable
      attributes!.add(Attribute.New(attributeFavorite, "true", appOrigin));
    } else {
      if (attributes != null) {
        attributes = attributes!.toList(); // ensure growable
      }
      final i = attributes?.indexWhere((element) => element.key == attributeFavorite);
      if (i != null && i != -1) {
        attributes!.removeAt(i);
      }
    }
  }

  toggleFavorite() {
    setFavorite(!favorite);
  }

  @JsonKey(ignore: true)
  @ignore
  DeviceConnectionStatus get connectionStatus {
    if (annotations?.connected == null) {
      return DeviceConnectionStatus.unknown;
    }
    if (annotations!.connected!) {
      return DeviceConnectionStatus.online;
    } else {
      return DeviceConnectionStatus.offline;
    }
  }

  @JsonKey(ignore: true)
  set connectionStatus(DeviceConnectionStatus connectionStatus) {
    switch (connectionStatus) {
      case DeviceConnectionStatus.unknown:
        if (annotations?.connected != null) {
          annotations!.connected = null;
        }
        break;
      case DeviceConnectionStatus.online:
        if (annotations != null) {
          annotations!.connected = true;
        } else {
          annotations = Annotations.New(true);
        }
        break;
      case DeviceConnectionStatus.offline:
        if (annotations != null) {
          annotations!.connected = false;
        } else {
          annotations = Annotations.New(false);
        }
        break;
    }
  }

  @ignore
  String get displayName => display_name ?? name;

  setNickname(String val) {
    final i = attributes?.indexWhere((element) => element.key == attributeNickname);
    if (i != null && i != -1) {
      attributes![i].value = val;
    } else {
      attributes ??= [];
      attributes = attributes!.toList(); // ensure growable
      attributes!.add(Attribute.New(attributeNickname, val, sharedOrigin));
    }
    display_name = val;
  }
}

class CommandCallback {
  DeviceCommand command;
  Function(dynamic value) callback;

  CommandCallback(this.command, this.callback);
}
