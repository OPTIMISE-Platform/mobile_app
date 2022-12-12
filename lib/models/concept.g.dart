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
