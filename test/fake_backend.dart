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

/// Answers by path and records every request. Dio's own status validation
/// still runs on what it returns, so a 404 arrives as it would from a server.
class FakeBackend implements HttpClientAdapter {
  final Map<String, int> status = {};
  final Map<String, List<Map<String, dynamic>>> types = {};
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final path = options.uri.path;
    final code = status[path] ?? 200;
    if (code != 200) return ResponseBody.fromString("", code);
    final all = types[path] ?? [];
    final offset = int.parse(options.uri.queryParameters["offset"] ?? "0");
    final limit = int.parse(options.uri.queryParameters["limit"] ?? "100");
    final page = all.skip(offset).take(limit).toList();
    return ResponseBody.fromString(jsonEncode(page), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
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
