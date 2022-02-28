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
      json['concept_id'] as String?,
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
      'concept_id': instance.concept_id,
      'type': instance.type,
      'sub_content_variables': instance.sub_content_variables,
      'value': instance.value,
      'serialization_options': instance.serialization_options,
    };
