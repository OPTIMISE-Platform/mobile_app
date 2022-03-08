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

part of 'concept.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Concept _$ConceptFromJson(Map<String, dynamic> json) => Concept(
      json['id'] as String,
      json['name'] as String,
      json['base_characteristic_id'] as String,
      (json['characteristic_ids'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      json['base_characteristic'] == null
          ? null
          : Characteristic.fromJson(
              json['base_characteristic'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$ConceptToJson(Concept instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'base_characteristic_id': instance.base_characteristic_id,
      'characteristic_ids': instance.characteristic_ids,
      'base_characteristic': instance.base_characteristic,
    };
