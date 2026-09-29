// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_state.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DeviceState _$DeviceStateFromJson(Map<String, dynamic> json) =>
    DeviceState(
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
        aspectIds: (json['aspectIds'] as List<dynamic>?)
            ?.map((e) => e as String)
            .toList(),
      )
      ..transitioning = json['transitioning'] as bool
      ..deviceInstance = json['deviceInstance'] == null
          ? null
          : DeviceInstance.fromJson(
              json['deviceInstance'] as Map<String, dynamic>,
            )
      ..deviceGroup = json['deviceGroup'] == null
          ? null
          : DeviceGroup.fromJson(json['deviceGroup'] as Map<String, dynamic>)
      ..name = json['name'] as String?;

Map<String, dynamic> _$DeviceStateToJson(DeviceState instance) =>
    <String, dynamic>{
      'value': instance.value,
      'functionId': instance.functionId,
      'isControlling': instance.isControlling,
      'transitioning': instance.transitioning,
      'deviceInstance': instance.deviceInstance,
      'deviceGroup': instance.deviceGroup,
      'serviceId': instance.serviceId,
      'serviceGroupKey': instance.serviceGroupKey,
      'groupId': instance.groupId,
      'deviceClassId': instance.deviceClassId,
      'deviceId': instance.deviceId,
      'path': instance.path,
      'name': instance.name,
      'serviceGroupName': instance.serviceGroupName,
      'aspectIds': instance.aspectIds,
      'aspectId': instance.aspectId,
    };
