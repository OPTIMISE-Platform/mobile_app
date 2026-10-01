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

import 'package:dio/dio.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/services/mgw/restricted.dart';

class MgwApiService {
  // Use this service to access the MGW auth-secured core API
  // Session Tokens are handles automatically

  String baseUrl = "/core/api";
  final MgwService mgwService;

  /// The core API of [gateway], with the session of its pairing.
  MgwApiService.forGateway(MGW gateway, {bool requireSession = false})
      : mgwService =
            MgwService.forGateway(gateway, requireSession: requireSession);

  /// The core API at [host] without a session.
  MgwApiService.unauthenticated(String host)
      : mgwService = MgwService.unauthenticated(host);

  Future<Response<dynamic>> Post(String path, dynamic data, Options options) async {
    return await mgwService.Post(baseUrl+path, data, options);
  }

  Future<Response<dynamic>> Get(String path, Options options) async {
    return await mgwService.Get(baseUrl+path, options);
  }
}
