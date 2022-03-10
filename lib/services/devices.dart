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

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:dio_cache_interceptor/dio_cache_interceptor.dart';
import 'package:dio_cache_interceptor_hive_store/dio_cache_interceptor_hive_store.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/services/cache_helper.dart';

import 'auth.dart';
import '../exceptions/unexpected_status_code_exception.dart';

class DevicesService {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );


  static late final Dio? _dio;
  static CacheOptions? _options;

  static initOptions() async {
    if (_options != null && _dio != null) {
      return;
    }

    String? cacheFile = await CacheHelper.getCacheFile();

    _options = CacheOptions(
      store: HiveCacheStore(cacheFile),
      policy: CachePolicy.refreshForceCache,
      hitCacheOnErrorExcept: [401, 403],
      maxStale: const Duration(days: 7),
      priority: CachePriority.normal,
      allowPostMethod: true,
      keyBuilder: CacheHelper.bodyCacheIDBuilder,
    );
    _dio = Dio()
      ..interceptors.add(DioCacheInterceptor(options: _options!));
  }

  static Future<List<DeviceInstance>> getDevices(BuildContext context, AppState state,
  int limit, int offset, String search, [List<String>? byDeviceTypes]) async {
    _logger.d("Devices '" +
        search +
        "' " +
        offset.toString() +
        "-" +
        (offset + limit).toString() +
        (byDeviceTypes != null ? (" types: " + byDeviceTypes.join(",")) : ""));

    final uri = (dotenv.env["API_URL"] ?? 'localhost') + '/permissions/query/v3/query';
    final body = <String, dynamic>{
      "resource": "devices",
      "find": {
        "limit": limit,
        "offset": offset,
        "sortBy": "name.asc",
        "search": search,
      }
    };
    if (byDeviceTypes != null && byDeviceTypes.isNotEmpty) {
      body["find"]["filter"] = {
        "condition": {
          "feature": "features.device_type_id",
          "operation": "any_value_in_feature",
          "value": byDeviceTypes,
        }
      };
    }

    final encoded = json.encode(body);

    final headers = await Auth.getHeaders(context, state);
    await initOptions();
    final resp = await _dio!.post<List<dynamic>?>(uri, options: Options(headers: headers), data: encoded);


    if (resp.statusCode == null || resp.statusCode! > 304) {
      throw UnexpectedStatusCodeException(resp.statusCode);
    }

    if (resp.statusCode == 304) {
      _logger.d("Using cached devices");
    }

    final l = resp.data ?? [];
    return List<DeviceInstance>.generate(
        l.length, (index) => DeviceInstance.fromJson(l[index]));
  }

  static Future<int> getTotalDevices(
      BuildContext context, AppState state, String search) async {
    String uri = (dotenv.env["API_URL"] ?? 'localhost') +
        '/permissions/query/v3/total/devices';

    final Map<String, String> queryParameters = {};
    if (search.isNotEmpty) {
      queryParameters["search"] = search;
    }
    final headers = await Auth.getHeaders(context, state);
    await initOptions();
    final resp = await _dio!.get<int>(uri, options: Options(headers: headers), queryParameters: queryParameters);

    if (resp.statusCode == null || resp.statusCode! > 304) {
      throw UnexpectedStatusCodeException(resp.statusCode);
    }

    if (resp.statusCode == 304) {
      _logger.d("Using cached total devices");
    }

    return resp.data ?? 0;
  }
}
