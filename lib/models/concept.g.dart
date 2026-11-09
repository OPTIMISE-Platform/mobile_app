// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'concept.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Concept _$ConceptFromJson(Map<String, dynamic> json) => Concept(
  json['id'] as String,
  json['name'] as String,
  json['base_characteristic_id'] as String,
  (json['characteristics'] as List<dynamic>)
      .map((e) => Characteristic.fromJson(e as Map<String, dynamic>))
      .toList(),
  (json['conversions'] as List<dynamic>?)
      ?.map((e) => ConceptConversion.fromJson(e as Map<String, dynamic>))
      .toList(),
);

Map<String, dynamic> _$ConceptToJson(Concept instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'base_characteristic_id': instance.base_characteristic_id,
  'characteristics': instance.characteristics,
  'conversions': instance.conversions,
};

ConceptConversion _$ConceptConversionFromJson(Map<String, dynamic> json) =>
    ConceptConversion(
      json['from'] as String,
      json['to'] as String,
      (json['distance'] as num).toInt(),
      json['formula'] as String,
      json['placeholder_name'] as String,
    );

Map<String, dynamic> _$ConceptConversionToJson(ConceptConversion instance) =>
    <String, dynamic>{
      'from': instance.from,
      'to': instance.to,
      'distance': instance.distance,
      'formula': instance.formula,
      'placeholder_name': instance.placeholder_name,
    };
