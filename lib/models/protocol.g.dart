// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'protocol.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Protocol _$ProtocolFromJson(Map<String, dynamic> json) => Protocol(
  json['id'] as String,
  json['name'] as String?,
  (json['protocol_segments'] as List<dynamic>?)
          ?.map((e) => ProtocolSegment.fromJson(e as Map<String, dynamic>))
          .toList() ??
      [],
);

Map<String, dynamic> _$ProtocolToJson(Protocol instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'protocol_segments': instance.protocol_segments,
};

ProtocolSegment _$ProtocolSegmentFromJson(Map<String, dynamic> json) =>
    ProtocolSegment(json['id'] as String, json['name'] as String);

Map<String, dynamic> _$ProtocolSegmentToJson(ProtocolSegment instance) =>
    <String, dynamic>{'id': instance.id, 'name': instance.name};
