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

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_command.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DeviceCommand _$DeviceCommandFromJson(Map<String, dynamic> json) =>
    DeviceCommand(
      json['function_id'] as String,
      json['device_id'] as String?,
      json['service_id'] as String?,
      json['aspect_id'] as String?,
      json['group_id'] as String?,
      json['device_class_id'] as String?,
      json['input'],
    );

Map<String, dynamic> _$DeviceCommandToJson(DeviceCommand instance) =>
    <String, dynamic>{
      'function_id': instance.function_id,
      'device_id': instance.device_id,
      'group_id': instance.group_id,
      'device_class_id': instance.device_class_id,
      'service_id': instance.service_id,
      'aspect_id': instance.aspect_id,
      'input': instance.input,
    };
