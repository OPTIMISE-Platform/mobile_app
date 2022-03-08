// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_command.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DeviceCommand _$DeviceCommandFromJson(Map<String, dynamic> json) =>
    DeviceCommand(
      json['function_id'] as String,
      json['device_id'] as String,
      json['service_id'] as String,
    )..input = json['input'];

Map<String, dynamic> _$DeviceCommandToJson(DeviceCommand instance) =>
    <String, dynamic>{
      'function_id': instance.function_id,
      'device_id': instance.device_id,
      'service_id': instance.service_id,
      'input': instance.input,
    };
