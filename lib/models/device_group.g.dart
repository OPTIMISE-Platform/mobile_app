// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_group.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

DeviceGroup _$DeviceGroupFromJson(Map<String, dynamic> json) => DeviceGroup(
      json['id'] as String,
      json['name'] as String,
      (json['criteria'] as List<dynamic>)
          .map((e) => DeviceGroupCriteria.fromJson(e as Map<String, dynamic>))
          .toList(),
      json['image'] as String,
      (json['device_ids'] as List<dynamic>).map((e) => e as String).toList(),
      (json['attributes'] as List<dynamic>?)
          ?.map((e) => Attribute.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$DeviceGroupToJson(DeviceGroup instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'image': instance.image,
      'criteria': instance.criteria,
      'device_ids': instance.device_ids,
      'attributes': instance.attributes,
    };

DeviceGroupCriteria _$DeviceGroupCriteriaFromJson(Map<String, dynamic> json) =>
    DeviceGroupCriteria(
      json['aspect_id'] as String,
      json['device_class_id'] as String,
      json['function_id'] as String,
      json['interaction'] as String,
    );

Map<String, dynamic> _$DeviceGroupCriteriaToJson(
        DeviceGroupCriteria instance) =>
    <String, dynamic>{
      'aspect_id': instance.aspect_id,
      'device_class_id': instance.device_class_id,
      'function_id': instance.function_id,
      'interaction': instance.interaction,
    };
