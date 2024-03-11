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

part 'mgw_deployment.g.dart';

@JsonSerializable()
class Endpoint {
  String id, location, ref;

  Endpoint(this.id, this.location, this.ref);
  factory Endpoint.fromJson(Map<String, dynamic> json) => _$EndpointFromJson(json);
  Map<String, dynamic> toJson() => _$EndpointToJson(this);
}

@JsonSerializable()
class Deployment {
  String id, name, updated, created;
  String? state;
  bool enabled;
  DeploymentModuleInfo module;

  Deployment(this.id, this.name, this.updated, this.created, this.state, this.enabled, this.module);
  factory Deployment.fromJson(Map<String, dynamic> json) => _$DeploymentFromJson(json);
  Map<String, dynamic> toJson() => _$DeploymentToJson(this);
}

class DeploymentModuleInfo {
  String id, version;

  DeploymentModuleInfo(this.id, this.version);
  DeploymentModuleInfo.fromJson(Map<String, dynamic> json): id=json['id'], version=json['version'];
  Map<String, dynamic> toJson() => <String, dynamic> {
    "id": this.id,
    "version": this.version
  };
}