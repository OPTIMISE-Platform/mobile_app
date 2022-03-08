// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'function.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Function _$FunctionFromJson(Map<String, dynamic> json) => Function(
      json['id'] as String,
      json['name'] as String,
      json['concept_id'] as String,
    );

Map<String, dynamic> _$FunctionToJson(Function instance) => <String, dynamic>{
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
