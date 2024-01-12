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
import 'package:mobile_app/models/device_group.dart';

import 'package:mobile_app/models/device_instance.dart';

part 'device_command.g.dart';

@JsonSerializable()
class DeviceCommand {
  String function_id;
  String? device_id, group_id, device_class_id, service_id, aspect_id, characteristic_id;
  dynamic input;
  DeviceInstance? deviceInstance;
  DeviceGroup? deviceGroup;

  DeviceCommand(this.function_id, this.device_id, this.service_id, this.aspect_id, [this.group_id, this.device_class_id, this.input, this.characteristic_id]);
  factory DeviceCommand.fromJson(Map<String, dynamic> json) => _$DeviceCommandFromJson(json);
  Map<String, dynamic> toJson() => _$DeviceCommandToJson(this);
}
