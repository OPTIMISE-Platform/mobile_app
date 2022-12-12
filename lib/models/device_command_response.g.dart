// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_command_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DeviceCommandResponse _$DeviceCommandResponseFromJson(
        Map<String, dynamic> json) =>
    DeviceCommandResponse(
      json['status_code'] as int,
      json['message'],
    );

Map<String, dynamic> _$DeviceCommandResponseToJson(
        DeviceCommandResponse instance) =>
    <String, dynamic>{
      'status_code': instance.status_code,
      'message': instance.message,
    };
