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
import 'package:mobile_app/services/mgw/restricted.dart';

class MgwApiService {
  MgwApiService._(this.mgwService);

  static const baseUrl = "/core/api";
  final MgwService mgwService;

  static Future<MgwApiService> create(String host, bool authenticate) async {
    final mgwService = await MgwService.create(host, authenticate);
    return MgwApiService._(mgwService);
  }

  Future<Response<dynamic>> Post(String path, dynamic data, Options options) async {
    return await mgwService.Post(baseUrl + path, data, options);
  }

  Future<Response<dynamic>> Get(String path, Options options) async {
    return await mgwService.Get(baseUrl + path, options);
  }
}
