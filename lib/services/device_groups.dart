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
import 'package:isar/isar.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/services/cache_helper.dart';

import '../exceptions/unexpected_status_code_exception.dart';
import '../models/attribute.dart';
import '../shared/http_client_adapter.dart';
import '../shared/isar.dart';
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
    _dio = Dio(BaseOptions(connectTimeout: 1500, sendTimeout: 5000, receiveTimeout: 5000))
      ..interceptors.add(DioCacheInterceptor(options: _options!))
      ..httpClientAdapter = AppHttpClientAdapter();
  }

  static Future<List<Future<DeviceGroup>>> getDeviceGroups({bool forceBackend = false}) async {
    final collection =  isar?.deviceGroups;

    if (!forceBackend && isar != null && collection != null) {
      return (await collection.where().sortByName().findAll()).map((e) => e.initImage()).toList();
    }

    String uri = '${dotenv.env["API_URL"] ?? 'localhost'}/permissions/query/v3/resources/device-groups';
    final Map<String, String> queryParameters = {};
    queryParameters["limit"] = "9999";

    final headers = await Auth().getHeaders();
    await initOptions();
    final Response<List<dynamic>?> resp;
    try {
      resp = await _dio!.get<List<dynamic>?>(uri, queryParameters: queryParameters, options: Options(headers: headers));
    } on DioError catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 304) {
        throw UnexpectedStatusCodeException(e.response?.statusCode);
      }
      rethrow;
    }
    if (resp.statusCode == 304) {
      _logger.d("Using cached device groups");
    }

    final l = resp.data ?? [];
    final groups = List<DeviceGroup>.generate(l.length, (index) => DeviceGroup.fromJson(l[index]));
    if (isar != null && collection != null) {
      await isar!.writeTxn(() async {
        await collection.putAll(groups);
      });
    }
    return groups.map((e) => e.initImage()).toList(growable: false);
  }

  static Future<DeviceGroup> saveDeviceGroup(DeviceGroup group) async {
    _logger.d("Saving device group: ${group.id}");

    final uri = "${dotenv.env["API_URL"] ?? 'localhost'}/device-manager/device-groups/${group.id}?update-only-same-origin-attributes=$appOrigin";

    final encoded = json.encode(group.toJson());

    final headers = await Auth().getHeaders();
    await initOptions();
    final Response<Map<String, dynamic>> resp;
    try {
      resp = await _dio!.put<Map<String, dynamic>>(uri, options: Options(headers: headers), data: encoded);
    } on DioError catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 299) {
        throw UnexpectedStatusCodeException(e.response?.statusCode);
      }
      rethrow;
    }

    final savedGroup = DeviceGroup.fromJson(resp.data!);

    if (isar != null) {
      await isar!.writeTxn(() async {
        await isar!.deviceGroups.put(savedGroup);
      });
    }

    return savedGroup;
  }

  static Future<DeviceGroup> createDeviceGroup(String name) async {
    String uri = '${dotenv.env["API_URL"] ?? 'localhost'}/device-manager/device-groups/';

    final headers = await Auth().getHeaders();
    await initOptions();
    final dio = Dio()..interceptors.add(DioCacheInterceptor(options: _options!))..httpClientAdapter = AppHttpClientAdapter();
    final Response<dynamic> resp;
    try {
      resp = await dio.post<dynamic>(uri, options: Options(headers: headers), data: DeviceGroup("", name, [], "", [], []).toJson());
    } on DioError catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 299) {
        throw UnexpectedStatusCodeException(e.response?.statusCode);
      }
      rethrow;
    }
    final savedGroup =  DeviceGroup.fromJson(resp.data);
    if (isar != null) {
      await isar!.writeTxn(() async {
        await isar!.deviceGroups.put(savedGroup);
      });
    }

    return savedGroup.initImage();
  }

  static Future<void> deleteDeviceGroup(String id) async {
    String uri = '${dotenv.env["API_URL"] ?? 'localhost'}/device-manager/device-groups/$id';

    final headers = await Auth().getHeaders();
    await initOptions();
    final dio = Dio()..interceptors.add(DioCacheInterceptor(options: _options!))..httpClientAdapter = AppHttpClientAdapter();
    try {
      await dio.delete(uri, options: Options(headers: headers));
    } on DioError catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 299) {
        throw UnexpectedStatusCodeException(e.response?.statusCode);
      }
      rethrow;
    }

    if (isar != null) {
      await isar!.writeTxn(() async {
        await isar!.deviceGroups.delete(fastHash(id));
      });
    }

    return;
  }

  static Future<DeviceGroupHelperResponse> getMatchingDevicesForGroup(List<String> deviceIds, int limit, int offset, String search) async {
    String uri = '${dotenv.env["API_URL"] ?? 'localhost'}/device-selection/device-group-helper';
    final Map<String, String> queryParameters = {};
    queryParameters["limit"] = limit.toString();
    queryParameters["offset"] = offset.toString();
    queryParameters["search"] = search;
    queryParameters["maintains_group_usability"] = "true";
    queryParameters["function_block_list"] = (dotenv.env["FUNCTION_GET_TIMESTAMP"] ?? "");

    final headers = await Auth().getHeaders();
    await initOptions();
    final Response<Map<String, dynamic>> resp;
    try {
      resp = await _dio!
          .post<Map<String, dynamic>>(uri, queryParameters: queryParameters, options: Options(headers: headers), data: json.encode(deviceIds));
    } on DioError catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 304) {
        throw UnexpectedStatusCodeException(e.response?.statusCode);
      }
      rethrow;
    }
    if (resp.statusCode == 304) {
      _logger.d("Using cached device groups");
    }

    final instances = (resp.data as Map<String, dynamic>)["options"] ?? [];
    final criteria = (resp.data as Map<String, dynamic>)["criteria"] ?? [];
    return DeviceGroupHelperResponse(
        List<DeviceGroupCriteria>.generate(criteria.length, (index) => DeviceGroupCriteria.fromJson(criteria[index])),
        List<DeviceInstanceWithRemovesCriteria>.generate(instances.length, (index) {
          instances[index]["device"]["shared"] = false;
          instances[index]["device"]["creator"] = "";
          return DeviceInstanceWithRemovesCriteria(
              DeviceInstance.fromJson(instances[index]["device"]), (instances[index]["removes_criteria"] as List<dynamic>).isNotEmpty);
        }));
  }
}
