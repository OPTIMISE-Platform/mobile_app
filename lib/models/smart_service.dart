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

import '../shared/keyed_list.dart';
import 'content_variable.dart';
import 'characteristic.dart';

part 'smart_service.g.dart';

@JsonSerializable()
class SmartServiceRelease {
  String description, design_id, id, name;
  String? error;
  int created_at;

  SmartServiceRelease(this.created_at, this.description, this.design_id, this.id, this.name, this.error);

  DateTime createdAt() {
    return DateTime.fromMillisecondsSinceEpoch(created_at * 1000).toLocal();
  }

  factory SmartServiceRelease.fromJson(Map<String, dynamic> json) => _$SmartServiceReleaseFromJson(json);

  Map<String, dynamic> toJson() => _$SmartServiceReleaseToJson(this);
}

@JsonSerializable()
class SmartServiceParameter {
  String id, label;
  String? value_label;
  dynamic value;

  SmartServiceParameter(this.id, this.value, this.label, this.value_label);

  factory SmartServiceParameter.fromJson(Map<String, dynamic> json) => _$SmartServiceParameterFromJson(json);

  Map<String, dynamic> toJson() => _$SmartServiceParameterToJson(this);
}

@JsonSerializable()
class SmartServiceParameterOption {
  String kind, label;
  String? entity_id, needs_same_entity_id_in_parameter;
  dynamic value;

  SmartServiceParameterOption(this.kind, this.label, this.value, this.needs_same_entity_id_in_parameter, this.entity_id);

  factory SmartServiceParameterOption.fromJson(Map<String, dynamic> json) => _$SmartServiceParameterOptionFromJson(json);

  Map<String, dynamic> toJson() => _$SmartServiceParameterOptionToJson(this);
}

@JsonSerializable()
class SmartServiceExtendedParameter {
  String id, label; //"inherited"
  // String? value_label; //"inherited" // in characteristic.value_label
  // dynamic value; //"inherited" //in characteristic.value

  String description;
  dynamic default_value;
  bool multiple;
  List<SmartServiceParameterOption>? options;
  ContentType type;
  String? characteristic_id;
  late Characteristic characteristic;

  SmartServiceExtendedParameter(this.id, this.label, this.description, dynamic value, this.default_value, this.multiple, this.options, this.type,
      String? value_label, this.characteristic_id, Characteristic? char) {
    characteristic = char ?? Characteristic(id, "", type, null, null, value, null, "", options);
    characteristic.value = value ?? default_value ?? characteristic.value;
    characteristic.value_label = value_label;
  }

  factory SmartServiceExtendedParameter.fromJson(Map<String, dynamic> json) => _$SmartServiceExtendedParameterFromJson(json);

  Map<String, dynamic> toJson() => _$SmartServiceExtendedParameterToJson(this);

  SmartServiceParameter toSmartServiceParameter() {
    if (value != null && options != null) {
      value_label = options!.firstWhere((element) => element.value == value).label;
    }
    return SmartServiceParameter(id, value, label, value_label);
  }

  dynamic get value {
    return characteristic.value;
  }

  set value(dynamic v) {
    characteristic.value = v;
  }

  String? get value_label {
    return characteristic.value_label;
  }

  set value_label(String? v) {
    characteristic.value_label = v;
  }
}

@JsonSerializable()
class SmartServiceInstance {
  String description, design_id, id, name, release_id, user_id;
  String? error, new_release_id;
  bool ready;
  bool? deleting;
  List<SmartServiceParameter>? parameters;

  SmartServiceInstance(this.description, this.design_id, this.id, this.name, this.release_id, this.user_id, this.error, this.ready, this.parameters, this.deleting, this.new_release_id);

  factory SmartServiceInstance.fromJson(Map<String, dynamic> json) => _$SmartServiceInstanceFromJson(json);

  Map<String, dynamic> toJson() => _$SmartServiceInstanceToJson(this);
}

typedef SmartServiceModuleType = String;

const SmartServiceModuleType smartServiceModuleTypeWidget = "widget";

@JsonSerializable()
class SmartServiceModule {
  String design_id, id, instance_id, release_id, user_id;
  SmartServiceModuleType module_type;
  dynamic module_data;

  SmartServiceModule(this.design_id, this.id, this.instance_id, this.release_id, this.user_id, this.module_type, this.module_data);

  factory SmartServiceModule.fromJson(Map<String, dynamic> json) => _$SmartServiceModuleFromJson(json);

  Map<String, dynamic> toJson() => _$SmartServiceModuleToJson(this);
}

@JsonSerializable()
class SmartServiceDashboard {
  String id, name;
  List<Pair<String, String>> widgetAndInstanceIds;

  SmartServiceDashboard(this.id, this.name, this.widgetAndInstanceIds);

  factory SmartServiceDashboard.fromJson(Map<String, dynamic> json) => _$SmartServiceDashboardFromJson(json);

  Map<String, dynamic> toJson() => _$SmartServiceDashboardToJson(this);
}
