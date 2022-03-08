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

part of 'function.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PlatformFunction _$PlatformFunctionFromJson(Map<String, dynamic> json) =>
    PlatformFunction(
      json['id'] as String,
      json['name'] as String,
      json['concept_id'] as String,
    );

Map<String, dynamic> _$PlatformFunctionToJson(PlatformFunction instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'concept_id': instance.concept_id,
    };

NestedFunction _$NestedFunctionFromJson(Map<String, dynamic> json) =>
    NestedFunction(
      json['id'] as String,
      json['name'] as String,
      json['concept_id'] as String,
      Concept.fromJson(json['concept'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$NestedFunctionToJson(NestedFunction instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'concept_id': instance.concept_id,
      'concept': instance.concept,
    };
