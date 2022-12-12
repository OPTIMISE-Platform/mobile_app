// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'network.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Network _$NetworkFromJson(Map<String, dynamic> json) => Network(
      json['id'] as String,
      json['name'] as String,
      json['annotations'] == null
          ? null
          : Annotations.fromJson(json['annotations'] as Map<String, dynamic>),
      json['shared'] as bool,
      json['creator'] as String,
      (json['device_local_ids'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      (json['device_ids'] as List<dynamic>?)?.map((e) => e as String).toList(),
    );

Map<String, dynamic> _$NetworkToJson(Network instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'creator': instance.creator,
      'annotations': instance.annotations,
      'shared': instance.shared,
      'device_local_ids': instance.device_local_ids,
      'device_ids': instance.device_ids,
    };
