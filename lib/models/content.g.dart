// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'content.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Content _$ContentFromJson(Map<String, dynamic> json) => Content(
      json['id'] as String,
      json['serialization'] as String,
      json['protocol_segment_id'] as String,
      ContentVariable.fromJson(
          json['content_variable'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$ContentToJson(Content instance) => <String, dynamic>{
      'id': instance.id,
      'serialization': instance.serialization,
      'protocol_segment_id': instance.protocol_segment_id,
      'content_variable': instance.content_variable,
    };
