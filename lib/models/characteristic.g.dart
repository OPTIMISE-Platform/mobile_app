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

part of 'characteristic.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Characteristic _$CharacteristicFromJson(Map<String, dynamic> json) => Characteristic(
      json['id'] as String,
      json['name'] as String,
      json['type'] as ContentType,
      (json['min_value'] as num?)?.toDouble(),
      (json['max_value'] as num?)?.toDouble(),
      json['value'],
      (json['sub_characteristics'] as List<dynamic>?)?.map((e) => Characteristic.fromJson(e as Map<String, dynamic>)).toList(),
      json['display_unit'] as String,
      json['allowed_values'] as List<dynamic>?,
    );

Map<String, dynamic> _$CharacteristicToJson(Characteristic instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'type': instance.type,
      'display_unit': instance.display_unit,
      'min_value': instance.min_value,
      'max_value': instance.max_value,
      'value': instance.value,
      'sub_characteristics': instance.sub_characteristics,
      'allowed_values': instance.allowed_values,
    };
