// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mgw_module.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Module _$ModuleFromJson(Map<String, dynamic> json) => Module(
  json['id'] as String,
  json['name'] as String,
  json['description'] as String,
  json['license'] as String,
  json['type'] as String,
  json['updated'] as String,
  json['added'] as String,
  json['deployment_type'] as String,
  json['version'] as String,
  json['author'] as String
);

Map<String, dynamic> _$ModuleToJson(Module instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'description': instance.description,
  'license': instance.license,
  'type': instance.type,
  'updated': instance.updated,
  'added': instance.added,
  'deployment_type': instance.deployment_type,
  'author': instance.author,
  'version': instance.version
};
