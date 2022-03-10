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

part of 'content_variable.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ContentVariable _$ContentVariableFromJson(Map<String, dynamic> json) =>
    ContentVariable(
      json['id'] as String?,
      json['name'] as String?,
      json['characteristic_id'] as String?,
      json['unit_reference'] as String?,
      json['aspect_id'] as String?,
      json['function_id'] as String?,
      json['type'] as String,
      (json['sub_content_variables'] as List<dynamic>?)
          ?.map((e) => ContentVariable.fromJson(e as Map<String, dynamic>))
          .toList(),
      json['value'],
      (json['serialization_options'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$ContentVariableToJson(ContentVariable instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'characteristic_id': instance.characteristic_id,
      'unit_reference': instance.unit_reference,
      'aspect_id': instance.aspect_id,
      'function_id': instance.function_id,
      'type': instance.type,
      'sub_content_variables': instance.sub_content_variables,
      'value': instance.value,
      'serialization_options': instance.serialization_options,
    };
