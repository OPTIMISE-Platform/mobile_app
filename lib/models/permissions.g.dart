// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'permissions.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Permissions _$PermissionsFromJson(Map<String, dynamic> json) => Permissions(
      json['a'] as bool,
      json['r'] as bool,
      json['w'] as bool,
      json['x'] as bool,
    );

Map<String, dynamic> _$PermissionsToJson(Permissions instance) =>
    <String, dynamic>{
      'a': instance.a,
      'r': instance.r,
      'w': instance.w,
      'x': instance.x,
    };
