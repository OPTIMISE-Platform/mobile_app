// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'service.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Service _$ServiceFromJson(Map<String, dynamic> json) => Service(
      json['id'] as String,
      json['local_id'] as String,
      json['name'] as String,
      json['description'] as String,
      json['protocol_id'] as String,
      json['interaction'] as String,
      json['service_group_key'] as String,
      (json['inputs'] as List<dynamic>)
          .map((e) => Content.fromJson(e as Map<String, dynamic>))
          .toList(),
      (json['outputs'] as List<dynamic>)
          .map((e) => Content.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$ServiceToJson(Service instance) => <String, dynamic>{
      'id': instance.id,
      'local_id': instance.local_id,
      'name': instance.name,
      'description': instance.description,
      'protocol_id': instance.protocol_id,
      'interaction': instance.interaction,
      'service_group_key': instance.service_group_key,
      'inputs': instance.inputs,
      'outputs': instance.outputs,
    };
