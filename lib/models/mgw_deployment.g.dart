// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mgw_deployment.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Endpoint _$EndpointFromJson(Map<String, dynamic> json) => Endpoint(
    json['id'] as String,
    json['location'] as String,
    json['ref'] as String,
);

Map<String, dynamic> _$EndpointToJson(Endpoint instance) => <String, dynamic>{
  'id': instance.id,
  'ref': instance.ref,
  'location': instance.location,
};

Deployment _$DeploymentFromJson(Map<String, dynamic> json) => Deployment(
  json['id'] as String,
  json['name'] as String,
  json['updated'] as String,
  json['created'] as String,
  json['state'],
  json['enabled'] as bool,
    DeploymentModuleInfo.fromJson(json['module'])
);

Map<String, dynamic> _$DeploymentToJson(Deployment instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name
};