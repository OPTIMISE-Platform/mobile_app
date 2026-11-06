/*
 * Copyright 2026 InfAI (CC SES)
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

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'fake_backend.dart';

const processesBase = "/automation-engine/namespaces/processes";

/// The process engine's list endpoints, answering `{items, total, limit,
/// offset}` sliced by each request's offset and limit, and the per-instance
/// debug route. Anything else falls through to [FakeBackend].
class ProcessBackend extends FakeBackend {
  final List<Map<String, dynamic>> deployments;
  final List<Map<String, dynamic>> instances;
  final Map<String, Map<String, dynamic>> debugs;

  /// When set, the deployments list answers with this status and no body.
  int? deploymentsStatus;
  ProcessBackend(
      {this.deployments = const [],
      this.instances = const [],
      this.debugs = const {}});

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final path = options.uri.path;
    final list = switch (path) {
      "$processesBase/deployments" => deployments,
      "$processesBase/instances" => instances,
      _ => null,
    };
    if (path == "$processesBase/deployments" && deploymentsStatus != null) {
      requests.add(options);
      return ResponseBody.fromString("", deploymentsStatus!);
    }
    if (list != null && !failures.containsKey("GET $path")) {
      requests.add(options);
      final offset = int.parse(options.uri.queryParameters["offset"] ?? "0");
      final limit = int.parse(options.uri.queryParameters["limit"] ?? "50");
      return _json({
        "items": list.skip(offset).take(limit).toList(),
        "total": list.length,
        "limit": limit,
        "offset": offset,
      });
    }
    const prefix = "$processesBase/instances/";
    if (path.startsWith(prefix) && path.endsWith("/debug")) {
      requests.add(options);
      final id = path.substring(prefix.length, path.length - "/debug".length);
      final debug = debugs[id];
      return debug == null ? ResponseBody.fromString("", 404) : _json(debug);
    }
    return super.fetch(options, requestStream, cancelFuture);
  }

  ResponseBody _json(Object body) =>
      ResponseBody.fromString(jsonEncode(body), 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });
}

Map<String, dynamic> deploymentJson(String id, String name,
        {String networkId = "", String description = ""}) =>
    {
      "id": id,
      "name": name,
      "description": description,
      "network_id": networkId,
      "model_id": "model-$id",
      "version": 1,
      "created_at": "2026-11-01T10:00:00.000Z",
      "updated_at": "2026-11-01T10:00:00.000Z",
    };

Map<String, dynamic> instanceJson(String id, String deploymentId, String name,
        {String state = "running",
        String createdAt = "2026-11-06T10:00:00.000Z",
        String? lastActivityAt,
        String networkId = ""}) =>
    {
      "id": id,
      "deployment_id": deploymentId,
      "deployment_name": name,
      "state": state,
      "status": state,
      "run": 1,
      "created_at": createdAt,
      "started_at": createdAt,
      if (lastActivityAt != null) "last_activity_at": lastActivityAt,
      if (networkId.isNotEmpty) "network_id": networkId,
    };

Map<String, dynamic> timerDebugJson(String elementId, String name,
        DateTime due) =>
    {
      "instance": {},
      "active": [
        {
          "element_id": elementId,
          "element_type": "intermediateCatchEvent",
          "name": name,
          "since": DateTime.now().toUtc().toIso8601String(),
          "tokens": 1
        }
      ],
      "waits": [
        {
          "element_id": elementId,
          "kind": "timer",
          "since": DateTime.now().toUtc().toIso8601String(),
          "timer": {
            "definition": "PT15M",
            "kind": "duration",
            "due_at": due.toUtc().toIso8601String()
          }
        }
      ],
      "variables": {},
      "incidents": [],
      "elements": [],
    };
