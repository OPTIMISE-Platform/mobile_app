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

import 'package:isar_community/isar.dart';
import 'package:json_annotation/json_annotation.dart';

import '../shared/isar.dart';

part 'mgw_deployment.g.dart';

@JsonSerializable()
@collection
class Endpoint {
  String id, location, ref;

  @JsonKey(includeFromJson: false, includeToJson: false)
  @Index()
  String moduleName;

  @JsonKey(includeFromJson: false, includeToJson: false)
  Id isarId = Isar.autoIncrement;

  Endpoint(this.id, this.location, this.ref, {this.moduleName = ""}){
    isarId = fastHash(id);
  }
  factory Endpoint.fromJson(Map<String, dynamic> json) => _$EndpointFromJson(json);
  Map<String, dynamic> toJson() => _$EndpointToJson(this);
}

/// Deployment of a module, as the module-manager reports it alongside the
/// module itself. A module without a deployment carries a zero value here, so
/// read it only when [Module.is_deployed] is set.
class Deployment {
  String id, module_source, module_channel, module_version, updated, created;
  bool enabled;

  /// Health derived from the container states: 1 healthy, 2 unhealthy, 0 when
  /// the deployment is disabled or the state could not be determined.
  int state;

  bool has_error;
  String error_msg;

  Deployment(this.id, this.module_source, this.module_channel,
      this.module_version, this.updated, this.created, this.enabled, this.state,
      {this.has_error = false, this.error_msg = ""});

  Deployment.fromJson(Map<String, dynamic> json)
      : id = json['id'] ?? "",
        module_source = json['module_source'] ?? "",
        module_channel = json['module_channel'] ?? "",
        module_version = json['module_version'] ?? "",
        updated = json['updated'] ?? "",
        created = json['created'] ?? "",
        enabled = json['enabled'] ?? false,
        state = json['state'] ?? 0,
        has_error = json['has_error'] ?? false,
        error_msg = json['error_msg'] ?? "";

  Map<String, dynamic> toJson() => <String, dynamic>{
        "id": id,
        "module_source": module_source,
        "module_channel": module_channel,
        "module_version": module_version,
        "updated": updated,
        "created": created,
        "enabled": enabled,
        "state": state,
        "has_error": has_error,
        "error_msg": error_msg,
      };
}