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

import 'package:mobile_app/models/mgw_deployment.dart';

/// Installed module as `GET /modules-reduced` reports it.
///
/// The deployment is nested here rather than fetched separately; the
/// module-manager has no deployments collection to read from.
class Module {
  String id, source, channel, version, name, description, license, author;
  List<String> tags;
  bool is_deployed;
  Deployment deployment;
  bool has_error;
  String error_msg;

  Module(this.id, this.source, this.channel, this.version, this.name,
      this.description, this.license, this.author, this.tags, this.is_deployed,
      this.deployment,
      {this.has_error = false, this.error_msg = ""});

  Module.fromJson(Map<String, dynamic> json)
      : id = json['id'] ?? "",
        source = json['source'] ?? "",
        channel = json['channel'] ?? "",
        version = json['version'] ?? "",
        name = json['name'] ?? "",
        description = json['description'] ?? "",
        license = json['license'] ?? "",
        author = json['author'] ?? "",
        tags = ((json['tags'] ?? []) as List).map((e) => e as String).toList(),
        is_deployed = json['is_deployed'] ?? false,
        deployment =
            Deployment.fromJson(json['deployment'] ?? <String, dynamic>{}),
        has_error = json['has_error'] ?? false,
        error_msg = json['error_msg'] ?? "";

  Map<String, dynamic> toJson() => <String, dynamic>{
        "id": id,
        "source": source,
        "channel": channel,
        "version": version,
        "name": name,
        "description": description,
        "license": license,
        "author": author,
        "tags": tags,
        "is_deployed": is_deployed,
        "deployment": deployment.toJson(),
        "has_error": has_error,
        "error_msg": error_msg,
      };
}
