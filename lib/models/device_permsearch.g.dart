// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_permsearch.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DevicePermSearch _$DevicePermSearchFromJson(Map<String, dynamic> json) =>
    DevicePermSearch(
      json['id'] as String,
      json['local_id'] as String,
      json['name'] as String,
      (json['attributes'] as List<dynamic>?)
          ?.map((e) => Attribute.fromJson(e as Map<String, dynamic>))
          .toList(),
      json['device_type_id'] as String,
      json['annotations'] == null
          ? null
          : Annotations.fromJson(json['annotations'] as Map<String, dynamic>),
      json['shared'] as bool,
      json['creator'] as String,
    );

Map<String, dynamic> _$DevicePermSearchToJson(DevicePermSearch instance) =>
    <String, dynamic>{
      'id': instance.id,
      'local_id': instance.local_id,
      'name': instance.name,
      'device_type_id': instance.device_type_id,
      'creator': instance.creator,
      'attributes': instance.attributes,
      'annotations': instance.annotations,
      'shared': instance.shared,
    };
