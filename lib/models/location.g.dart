// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'location.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Location _$LocationFromJson(Map<String, dynamic> json) => Location(
      json['id'] as String,
      json['name'] as String,
      json['description'] as String,
      json['image'] as String,
      (json['device_ids'] as List<dynamic>).map((e) => e as String).toList(),
      (json['device_group_ids'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$LocationToJson(Location instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
      'image': instance.image,
      'device_ids': instance.device_ids,
      'device_group_ids': instance.device_group_ids,
    };
