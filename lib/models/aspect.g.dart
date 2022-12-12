// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'aspect.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Aspect _$AspectFromJson(Map<String, dynamic> json) => Aspect(
      json['id'] as String,
      json['name'] as String,
      (json['sub_aspects'] as List<dynamic>?)
          ?.map((e) => Aspect.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$AspectToJson(Aspect instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'sub_aspects': instance.sub_aspects,
    };
