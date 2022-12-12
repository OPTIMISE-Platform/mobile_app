// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_command.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DeviceCommand _$DeviceCommandFromJson(Map<String, dynamic> json) =>
    DeviceCommand(
      json['function_id'] as String,
      json['device_id'] as String?,
      json['service_id'] as String?,
      json['aspect_id'] as String?,
      json['group_id'] as String?,
      json['device_class_id'] as String?,
      json['input'],
      json['characteristic_id'] as String?,
    )
      ..deviceInstance = json['deviceInstance'] == null
          ? null
          : DeviceInstance.fromJson(
              json['deviceInstance'] as Map<String, dynamic>)
      ..deviceGroup = json['deviceGroup'] == null
          ? null
          : DeviceGroup.fromJson(json['deviceGroup'] as Map<String, dynamic>);

Map<String, dynamic> _$DeviceCommandToJson(DeviceCommand instance) =>
    <String, dynamic>{
      'function_id': instance.function_id,
      'device_id': instance.device_id,
      'group_id': instance.group_id,
      'device_class_id': instance.device_class_id,
      'service_id': instance.service_id,
      'aspect_id': instance.aspect_id,
      'characteristic_id': instance.characteristic_id,
      'input': instance.input,
      'deviceInstance': instance.deviceInstance,
      'deviceGroup': instance.deviceGroup,
    };
