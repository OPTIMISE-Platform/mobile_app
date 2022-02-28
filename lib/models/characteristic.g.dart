// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'characteristic.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Characteristic _$CharacteristicFromJson(Map<String, dynamic> json) =>
    Characteristic(
      json['id'] as String,
      json['name'] as String,
      json['type'] as String,
      (json['min_value'] as num?)?.toDouble(),
      (json['max_value'] as num?)?.toDouble(),
      json['value'],
      (json['sub_characteristics'] as List<dynamic>?)
          ?.map((e) => Characteristic.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$CharacteristicToJson(Characteristic instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'type': instance.type,
      'min_value': instance.min_value,
      'max_value': instance.max_value,
      'value': instance.value,
      'sub_characteristics': instance.sub_characteristics,
    };
