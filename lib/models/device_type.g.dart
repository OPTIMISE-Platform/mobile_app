// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_type.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DeviceType _$DeviceTypeFromJson(Map<String, dynamic> json) => DeviceType(
      json['id'] as String,
      json['name'] as String,
      json['description'] as String,
      json['device_class_id'] as String,
      (json['services'] as List<dynamic>)
          .map((e) => Service.fromJson(e as Map<String, dynamic>))
          .toList(),
      (json['service_groups'] as List<dynamic>?)
          ?.map((e) => ServiceGroup.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$DeviceTypeToJson(DeviceType instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
      'device_class_id': instance.device_class_id,
      'services': instance.services,
      'service_groups': instance.service_groups,
    };
