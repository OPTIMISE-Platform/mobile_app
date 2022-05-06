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
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/services/cache_helper.dart';

import '../exceptions/unexpected_status_code_exception.dart';
import '../models/attribute.dart';
import 'auth.dart';

class DeviceGroupsService {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  static CacheOptions? _options;
  static late final Dio? _dio;

  static initOptions() async {
    if (_options != null) {
      return;
    }

    _options = CacheOptions(
      store: HiveCacheStore(await CacheHelper.getCacheFile()),
      policy: CachePolicy.refreshForceCache,
      hitCacheOnErrorExcept: [401, 403],
      maxStale: const Duration(days: 7),
      priority: CachePriority.normal,
      keyBuilder: CacheHelper.bodyCacheIDBuilder,
    );
    _dio = Dio()..interceptors.add(DioCacheInterceptor(options: _options!));
  }

  static Future<List<Future<DeviceGroup>>> getDeviceGroups() async {
    String uri = (dotenv.env["API_URL"] ?? 'localhost') +
        '/permissions/query/v3/resources/device-groups';
    final Map<String, String> queryParameters = {};
    queryParameters["limit"] = "9999";

    final headers = await Auth().getHeaders();
    await initOptions();
    final resp = await _dio!.get<List<dynamic>?>(uri,
        queryParameters: queryParameters, options: Options(headers: headers));
    if (resp.statusCode == null || resp.statusCode! > 304) {
      throw UnexpectedStatusCodeException(resp.statusCode);
    }
    if (resp.statusCode == 304) {
      _logger.d("Using cached device groups");
    }

    final l = resp.data ?? [];
    final groups = List<DeviceGroup>.generate(
        l.length, (index) => DeviceGroup.fromJson(l[index]));
    return groups.map((e) => e.initImage()).toList(growable: false);
  }

  static Future<DeviceGroup> saveDeviceGroup(DeviceGroup group) async {
    _logger.d("Saving device group: " + group.id);

    final uri = (dotenv.env["API_URL"] ?? 'localhost') + '/device-manager/device-groups/' + group.id + "?update-only-same-origin-attributes=" + appOrigin;

    final encoded = json.encode(group.toJson());

    final headers = await Auth().getHeaders();
    await initOptions();
    final resp = await _dio!.put<Map<String, dynamic>>(uri, options: Options(headers: headers), data: encoded);

    if (resp.statusCode == null || resp.statusCode! > 204) {
      throw UnexpectedStatusCodeException(resp.statusCode);
    }

    return DeviceGroup.fromJson(resp.data!);
  }
}
