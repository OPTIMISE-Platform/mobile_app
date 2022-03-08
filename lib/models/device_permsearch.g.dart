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

part of 'device_permsearch.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DevicePermSearch _$DevicePermSearchFromJson(Map<String, dynamic> json) =>
    DevicePermSearch(
      json['id'] as String,
      json['local_id'] as String,
      json['name'] as String,
      (json['attributes'] as List<dynamic>?)
          ?.map((e) => Attribute.fromJson(e as Map<String, dynamic>))
          .toList(),
      json['device_type_id'] as String,
      json['annotations'] == null
          ? null
          : Annotations.fromJson(json['annotations'] as Map<String, dynamic>),
      json['shared'] as bool,
      json['creator'] as String,
    );

Map<String, dynamic> _$DevicePermSearchToJson(DevicePermSearch instance) =>
    <String, dynamic>{
      'id': instance.id,
      'local_id': instance.local_id,
      'name': instance.name,
      'device_type_id': instance.device_type_id,
      'creator': instance.creator,
      'attributes': instance.attributes,
      'annotations': instance.annotations,
      'shared': instance.shared,
    };
