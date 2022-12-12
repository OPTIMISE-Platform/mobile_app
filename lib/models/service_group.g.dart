// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'service_group.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ServiceGroup _$ServiceGroupFromJson(Map<String, dynamic> json) => ServiceGroup(
      json['key'] as String,
      json['name'] as String,
      json['description'] as String,
    );

Map<String, dynamic> _$ServiceGroupToJson(ServiceGroup instance) =>
    <String, dynamic>{
      'key': instance.key,
      'name': instance.name,
      'description': instance.description,
    };
