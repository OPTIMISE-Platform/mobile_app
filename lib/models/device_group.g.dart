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

part of 'device_group.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DeviceGroup _$DeviceGroupFromJson(Map<String, dynamic> json) => DeviceGroup(
      json['id'] as String,
      json['name'] as String,
      (json['criteria'] as List<dynamic>)
          .map((e) => DeviceGroupCriteria.fromJson(e as Map<String, dynamic>))
          .toList(),
      json['image'] as String,
      (json['device_ids'] as List<dynamic>).map((e) => e as String).toList(),
    );

Map<String, dynamic> _$DeviceGroupToJson(DeviceGroup instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'image': instance.image,
      'criteria': instance.criteria,
      'device_ids': instance.device_ids,
    };

DeviceGroupCriteria _$DeviceGroupCriteriaFromJson(Map<String, dynamic> json) =>
    DeviceGroupCriteria(
      json['aspect_id'] as String,
      json['device_class_id'] as String,
      json['function_id'] as String,
      json['interaction'] as String,
    );

Map<String, dynamic> _$DeviceGroupCriteriaToJson(
        DeviceGroupCriteria instance) =>
    <String, dynamic>{
      'aspect_id': instance.aspect_id,
      'device_class_id': instance.device_class_id,
      'function_id': instance.function_id,
      'interaction': instance.interaction,
    };
