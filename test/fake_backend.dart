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
import 'package:mobile_app/services/device_types.dart';

/// Answers by (method, path) and records every request. Unmatched routes 404
/// and are recorded in [unmatchedRequests], so a golden test can assert or
/// print what a screen actually fetched.
///
/// [status] and [types] are the original device-types-only API: a path-keyed
/// status override and a paginated JSON list, kept for
/// device_types_service_test.dart and device_types_cache_test.dart. New
/// callers use [serveJson] instead.
class FakeBackend implements HttpClientAdapter {
  final Map<String, int> status = {};
  final Map<String, List<Map<String, dynamic>>> types = {};

  final Map<String, _Route> _routes = {};
  final List<RequestOptions> requests = [];
  final List<String> unmatchedRequests = [];

  /// Serves [statusCode] with [body] (JSON-encoded unless [contentType] says
  /// otherwise) for every request matching [method] and [path].
  void serveJson(String method, String path, int statusCode, dynamic body,
      {String contentType = Headers.jsonContentType}) {
    _routes['${method.toUpperCase()} $path'] =
        _Route(statusCode, body, contentType);
  }

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final path = options.uri.path;
    final key = '${options.method.toUpperCase()} $path';

    final route = _routes[key];
    if (route != null) {
      return _respond(route.status, route.body, route.contentType);
    }

    // Legacy paginated-list behaviour, for the device-types tests.
    if (types.containsKey(path) || status.containsKey(path)) {
      final code = status[path] ?? 200;
      if (code != 200) return ResponseBody.fromString("", code);
      final all = types[path] ?? [];
      final offset = int.parse(options.uri.queryParameters["offset"] ?? "0");
      final limit = int.parse(options.uri.queryParameters["limit"] ?? "100");
      final page = all.skip(offset).take(limit).toList();
      return _respond(200, page, Headers.jsonContentType);
    }

    unmatchedRequests.add(key);
    return ResponseBody.fromString("", 404);
  }

  ResponseBody _respond(int statusCode, dynamic body, String contentType) {
    final content =
        body == null ? "" : (body is String ? body : jsonEncode(body));
    return ResponseBody.fromString(content, statusCode, headers: {
      Headers.contentTypeHeader: [contentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

class _Route {
  final int status;
  final dynamic body;
  final String contentType;

  _Route(this.status, this.body, this.contentType);
}

const _base = "https://api.test/device-repository";

/// Points [DeviceTypesService] at [backend], with a fixed bearer token.
void serveDeviceTypes(FakeBackend backend) {
  final dio = Dio()..httpClientAdapter = backend;
  DeviceTypesService.uri = "$_base/device-types";
  DeviceTypesService.userUri = "$_base/user-device-types";
  DeviceTypesService.listDio = () async => dio;
  DeviceTypesService.listHeaders = () async => {"authorization": "Bearer t"};
}

Map<String, dynamic> deviceTypeJson(String id) => {
      "id": id,
      "name": id,
      "description": "",
      "device_class_id": "",
      "services": [],
    };

/// Wire shape of `DeviceInstance.fromJson`, for routes that hand a device
/// back from the backend (extended-devices, the group helper, ...).
Map<String, dynamic> deviceJson(String id, String name,
        {String deviceTypeId = "device-type-1",
        String connectionState = "online"}) =>
    {
      "id": id,
      "local_id": "$id-local",
      "name": name,
      "device_type_id": deviceTypeId,
      "shared": false,
      "owner_id": "owner-1",
      "display_name": name,
      "attributes": null,
      "connection_state": connectionState,
    };
