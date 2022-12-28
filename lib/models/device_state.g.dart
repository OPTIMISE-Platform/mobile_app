// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_state.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DeviceState _$DeviceStateFromJson(Map<String, dynamic> json) => DeviceState(
      json['value'],
      json['serviceId'] as String?,
      json['serviceGroupKey'] as String?,
      json['functionId'] as String,
      json['aspectId'] as String?,
      json['isControlling'] as bool,
      json['groupId'] as String?,
      json['deviceClassId'] as String?,
      json['deviceId'] as String?,
      json['path'] as String?,
      json['serviceGroupName'] as String?,
    )
      ..transitioning = json['transitioning'] as bool
      ..name = json['name'] as String?
      ..deviceInstance = json['deviceInstance'] == null
          ? null
          : DeviceInstance.fromJson(
              json['deviceInstance'] as Map<String, dynamic>)
      ..deviceGroup = json['deviceGroup'] == null
          ? null
          : DeviceGroup.fromJson(json['deviceGroup'] as Map<String, dynamic>);

Map<String, dynamic> _$DeviceStateToJson(DeviceState instance) =>
    <String, dynamic>{
      'value': instance.value,
      'functionId': instance.functionId,
      'isControlling': instance.isControlling,
      'transitioning': instance.transitioning,
      'serviceId': instance.serviceId,
      'serviceGroupKey': instance.serviceGroupKey,
      'aspectId': instance.aspectId,
      'groupId': instance.groupId,
      'deviceClassId': instance.deviceClassId,
      'deviceId': instance.deviceId,
      'path': instance.path,
      'name': instance.name,
      'serviceGroupName': instance.serviceGroupName,
      'deviceInstance': instance.deviceInstance,
      'deviceGroup': instance.deviceGroup,
    };
