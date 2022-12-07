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

part of 'network.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Network _$NetworkFromJson(Map<String, dynamic> json) => Network(
      json['id'] as String,
      json['name'] as String,
      json['annotations'] == null ? null : Annotations.fromJson(json['annotations'] as Map<String, dynamic>),
      json['shared'] as bool,
      json['creator'] as String,
      (json['device_local_ids'] as List<dynamic>?)?.map((e) => e as String).toList(),
      (json['device_ids'] as List<dynamic>?)?.map((e) => e as String).toList(),
    );

Map<String, dynamic> _$NetworkToJson(Network instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'creator': instance.creator,
      'annotations': instance.annotations,
      'shared': instance.shared,
      'device_local_ids': instance.device_local_ids,
      'device_ids': instance.device_ids,
    };
