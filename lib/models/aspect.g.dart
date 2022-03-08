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

part of 'aspect.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Aspect _$AspectFromJson(Map<String, dynamic> json) => Aspect(
      json['id'] as String,
      json['name'] as String,
      (json['sub_aspects'] as List<dynamic>?)
          ?.map((e) => Aspect.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$AspectToJson(Aspect instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'sub_aspects': instance.sub_aspects,
    };
