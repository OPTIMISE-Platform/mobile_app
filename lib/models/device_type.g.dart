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

part of 'device_type.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DeviceType _$DeviceTypeFromJson(Map<String, dynamic> json) => DeviceType(
      json['id'] as String,
      json['name'] as String,
      json['description'] as String,
      json['device_class_id'] as String,
      (json['service'] as List<dynamic>)
          .map((e) => Service.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$DeviceTypeToJson(DeviceType instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
      'device_class_id': instance.device_class_id,
      'service': instance.service,
    };
