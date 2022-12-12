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
      json['display_name'] as String,
    );

Map<String, dynamic> _$PlatformFunctionToJson(PlatformFunction instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'concept_id': instance.concept_id,
      'display_name': instance.display_name,
    };

NestedFunction _$NestedFunctionFromJson(Map<String, dynamic> json) =>
    NestedFunction(
      json['id'] as String,
      json['name'] as String,
      json['concept_id'] as String,
      json['display_name'] as String,
      Concept.fromJson(json['concept'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$NestedFunctionToJson(NestedFunction instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'concept_id': instance.concept_id,
      'display_name': instance.display_name,
      'concept': instance.concept,
    };
