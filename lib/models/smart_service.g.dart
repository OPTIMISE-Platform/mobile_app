/*
 * Copyright 2022 InfAI (CC SES)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 */

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'smart_service.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SmartServiceRelease _$SmartServiceReleaseFromJson(Map<String, dynamic> json) => SmartServiceRelease(
      json['created_at'] as int,
      json['description'] as String,
      json['design_id'] as String,
      json['id'] as String,
      json['name'] as String,
      json['error'] as String?,
      json['usable'] as bool?,
    );

Map<String, dynamic> _$SmartServiceReleaseToJson(SmartServiceRelease instance) => <String, dynamic>{
      'created_at': instance.created_at,
      'description': instance.description,
      'design_id': instance.design_id,
      'id': instance.id,
      'name': instance.name,
      'error': instance.error,
      'usable': instance.usable,
    };

SmartServiceParameter _$SmartServiceParameterFromJson(Map<String, dynamic> json) => SmartServiceParameter(
      json['id'] as String,
      json['value'],
      json['label'] as String,
      json['value_label'] as String?,
    );

Map<String, dynamic> _$SmartServiceParameterToJson(SmartServiceParameter instance) => <String, dynamic>{
      'id': instance.id,
      'value': instance.value,
      'label': instance.label,
      'value_label': instance.value_label,
    };

SmartServiceParameterOption _$SmartServiceParameterOptionFromJson(Map<String, dynamic> json) => SmartServiceParameterOption(
      json['kind'] as String,
      json['label'] as String,
      json['value'],
      json['needs_same_entity_id_in_parameter'] as String?,
      json['entity_id'] as String?,
    );

Map<String, dynamic> _$SmartServiceParameterOptionToJson(SmartServiceParameterOption instance) => <String, dynamic>{
      'kind': instance.kind,
      'label': instance.label,
      'value': instance.value,
      'needs_same_entity_id_in_parameter': instance.needs_same_entity_id_in_parameter,
      'entity_id': instance.entity_id,
    };

SmartServiceExtendedParameter _$SmartServiceExtendedParameterFromJson(Map<String, dynamic> json) => SmartServiceExtendedParameter(
      json['id'] as String,
      json['label'] as String,
      json['description'] as String,
      json['value'],
      json['default_value'],
      json['multiple'] as bool,
      (json['options'] as List<dynamic>?)?.map((e) => SmartServiceParameterOption.fromJson(e as Map<String, dynamic>)).toList(),
      json['type'] as String,
      json['value_label'] as String?,
      json['characteristic_id'] as String?,
      json['characteristic'] == null ? null : Characteristic.fromJson(json['characteristic']),
      json['optional'] as bool,
    );

Map<String, dynamic> _$SmartServiceExtendedParameterToJson(SmartServiceExtendedParameter instance) => <String, dynamic>{
      'id': instance.id,
      'value': instance.value,
      'label': instance.label,
      'description': instance.description,
      'default_value': instance.default_value,
      'multiple': instance.multiple,
      'options': instance.options,
      'type': instance.type,
      'value_label': instance.value_label,
      'characteristic_id': instance.characteristic_id,
      'characteristic': instance.characteristic.toJson(),
      'optional': instance.optional,
    };

SmartServiceInstance _$SmartServiceInstanceFromJson(Map<String, dynamic> json) => SmartServiceInstance(
      json['description'] as String,
      json['design_id'] as String,
      json['id'] as String,
      json['name'] as String,
      json['release_id'] as String,
      json['user_id'] as String,
      json['error'] as String?,
      json['ready'] as bool,
      (json['parameters'] as List<dynamic>?)?.map((e) => SmartServiceParameter.fromJson(e as Map<String, dynamic>)).toList(),
      json['deleting'] as bool?,
      json['new_release_id'] as String?
    );

Map<String, dynamic> _$SmartServiceInstanceToJson(SmartServiceInstance instance) => <String, dynamic>{
      'description': instance.description,
      'design_id': instance.design_id,
      'id': instance.id,
      'name': instance.name,
      'release_id': instance.release_id,
      'user_id': instance.user_id,
      'error': instance.error,
      'ready': instance.ready,
      'parameters': instance.parameters,
      'deleting': instance.deleting,
      'new_release_id': instance.new_release_id,
    };

SmartServiceModule _$SmartServiceModuleFromJson(Map<String, dynamic> json) => SmartServiceModule(
      json['design_id'] as String,
      json['id'] as String,
      json['instance_id'] as String,
      json['release_id'] as String,
      json['user_id'] as String,
      json['module_type'] as String,
      json['module_data'],
    );

Map<String, dynamic> _$SmartServiceModuleToJson(SmartServiceModule instance) => <String, dynamic>{
      'design_id': instance.design_id,
      'id': instance.id,
      'instance_id': instance.instance_id,
      'release_id': instance.release_id,
      'user_id': instance.user_id,
      'module_type': instance.module_type,
      'module_data': instance.module_data,
    };

SmartServiceDashboard _$SmartServiceDashboardFromJson(Map<String, dynamic> json) => SmartServiceDashboard(
      json['id'] as String,
      json['name'] as String,
      (json['widgetAndInstanceIds'] as List<dynamic>).map((e) => Pair<String, String>.fromJson(e)).toList(),
    );

Map<String, dynamic> _$SmartServiceDashboardToJson(SmartServiceDashboard instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'widgetAndInstanceIds': instance.widgetAndInstanceIds,
    };