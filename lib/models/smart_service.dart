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

import 'package:json_annotation/json_annotation.dart';

import 'content_variable.dart';

part 'smart_service.g.dart';

@JsonSerializable()
class SmartServiceRelease {
  String created_at, description, design_id, id, name;
  String? error;

  SmartServiceRelease(this.created_at, this.description, this.design_id, this.id, this.name, this.error);

  DateTime createdAt() {
    return DateTime.parse(created_at).toLocal();
  }

  factory SmartServiceRelease.fromJson(Map<String, dynamic> json) => _$SmartServiceReleaseFromJson(json);

  Map<String, dynamic> toJson() => _$SmartServiceReleaseToJson(this);
}

@JsonSerializable()
class SmartServiceParameter {
  String id;
  dynamic value;

  SmartServiceParameter(this.id, this.value);

  factory SmartServiceParameter.fromJson(Map<String, dynamic> json) => _$SmartServiceParameterFromJson(json);

  Map<String, dynamic> toJson() => _$SmartServiceParameterToJson(this);
}

@JsonSerializable()
class SmartServiceParameterOption {
  String kind, label;
  dynamic value;

  SmartServiceParameterOption(this.kind, this.label, this.value);

  factory SmartServiceParameterOption.fromJson(Map<String, dynamic> json) => _$SmartServiceParameterOptionFromJson(json);

  Map<String, dynamic> toJson() => _$SmartServiceParameterOptionToJson(this);
}

@JsonSerializable()
class SmartServiceExtendedParameter {
  String id; //"inherited"
  dynamic value; //"inherited"

  String  label, description;
  dynamic default_value;
  bool multiple;
  List<SmartServiceParameterOption>? options;
  ContentType type;

  SmartServiceExtendedParameter(this.id, this.label, this.description, this.value, this.default_value, this.multiple, this.options, this.type);

  factory SmartServiceExtendedParameter.fromJson(Map<String, dynamic> json) => _$SmartServiceExtendedParameterFromJson(json);

  Map<String, dynamic> toJson() => _$SmartServiceExtendedParameterToJson(this);

  SmartServiceParameter toSmartServiceParameter() {
    return SmartServiceParameter(id, value);
  }
}

@JsonSerializable()
class SmartServiceInstance {
  String description, design_id, id, name, release_id, user_id;
  bool incomplete_delete, ready;
  List<SmartServiceParameter>? parameters;

  SmartServiceInstance(
      this.description, this.design_id, this.id, this.name, this.release_id, this.user_id, this.incomplete_delete, this.ready, this.parameters);

  factory SmartServiceInstance.fromJson(Map<String, dynamic> json) => _$SmartServiceInstanceFromJson(json);

  Map<String, dynamic> toJson() => _$SmartServiceInstanceToJson(this);
}

typedef SmartServiceModuleType = String; // TODO define module types

@JsonSerializable()
class SmartServiceModule {
  String design_id, id, instance_id, release_id, user_id;
  SmartServiceModuleType module_type;
  dynamic module_data;

  SmartServiceModule(this.design_id, this.id, this.instance_id, this.release_id, this.user_id, this.module_type, this.module_data);

  factory SmartServiceModule.fromJson(Map<String, dynamic> json) => _$SmartServiceModuleFromJson(json);

  Map<String, dynamic> toJson() => _$SmartServiceModuleToJson(this);
}