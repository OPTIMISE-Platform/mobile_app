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
import 'package:logger/logger.dart';
import 'package:mobile_app/models/service_group.dart';

import 'service.dart';

part 'device_type.g.dart';

@JsonSerializable()
class DeviceType {
  String id, name, description, device_class_id;
  List<Service> services;
  List<ServiceGroup>? service_groups;

  DeviceType(
      this.id, this.name, this.description, this.device_class_id, this.services, this.service_groups);

  factory DeviceType.fromJson(Map<String, dynamic> json) =>
      _$DeviceTypeFromJson(json);

  Map<String, dynamic> toJson() => _$DeviceTypeToJson(this);
}

class DeviceTypePermSearch {
  String id, name, description, device_class_id;
  dynamic _service;

  static final _logger = Logger(printer: SimplePrinter());

  List<String> get service {
    if (_service is List<String>) {
      return _service;
    }
    if (_service is String) {
      return [_service];
    }
    _logger.w("unexpected type of service in device-type: " +
        _service.runtimeType.toString());
    return [];
  }

  DeviceTypePermSearch(this.id, this.name, this.description,
      this.device_class_id, this._service);

  factory DeviceTypePermSearch.fromJson(Map<String, dynamic> json) =>
      _$DeviceTypePermSearchFromJson(json);

  Map<String, dynamic> toJson() => _$DeviceTypePermSearchToJson(this);
}

DeviceTypePermSearch _$DeviceTypePermSearchFromJson(
        Map<String, dynamic> json) =>
    DeviceTypePermSearch(
      json['id'] as String,
      json['name'] as String,
      json['description'] as String,
      json['device_class_id'] as String,
      json['service'] as dynamic,
    );

Map<String, dynamic> _$DeviceTypePermSearchToJson(
        DeviceTypePermSearch instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
      'device_class_id': instance.device_class_id,
      'service': instance.service,
    };
