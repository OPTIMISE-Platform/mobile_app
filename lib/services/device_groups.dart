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
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/api_available_interceptor.dart';

import 'package:mobile_app/exceptions/unexpected_status_code_exception.dart';
import 'package:mobile_app/models/attribute.dart';
import 'package:mobile_app/shared/http_client_adapter.dart';
import 'package:mobile_app/shared/isar.dart';
import 'package:mobile_app/services/api_available.dart';
import 'package:mobile_app/services/auth.dart';

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
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(milliseconds: 1500),
      sendTimeout: const Duration(milliseconds: 5000),
      receiveTimeout: const Duration(milliseconds: 15000),
    ))
      ..interceptors.add(DioCacheInterceptor(options: _options!))
      ..interceptors.add(ApiAvailableInterceptor())
      ..httpClientAdapter = AppHttpClientAdapter();
  }

  static Future<List<Future<DeviceGroup>>> getDeviceGroups(
      {bool forceBackend = false}) async {
    final collection = isar?.deviceGroups;

    if (!forceBackend && isar != null && collection != null) {
      return (await collection.where().sortByName().findAll())
          .map((e) => e.initImage())
          .toList();
    }

    String uri =
        '${Settings.getApiUrl() ?? 'localhost'}/device-repository/device-groups';
    final Map<String, String> queryParameters = {};
    queryParameters["limit"] = "9999";
    var cont = true;
    final rawGroups = <DeviceGroup>[];
    final headers = await Auth().getHeaders();
    while (cont) {
      queryParameters["offset"] = rawGroups.length.toString();
      await initOptions();
      final Response<List<dynamic>?> resp;
      try {
        resp = await _dio!.get<List<dynamic>?>(uri,
            queryParameters: queryParameters,
            options: Options(headers: headers));
      } on DioException catch (e) {
        if (e.response?.statusCode == null || e.response!.statusCode! > 304) {
          throw UnexpectedStatusCodeException(
              e.response?.statusCode, "$uri ${e.message}");
        }
        rethrow;
      }
      if (resp.statusCode == 304) {
        _logger.d("Using cached device groups");
      }

      final l = resp.data ?? [];
      final add = List<DeviceGroup>.generate(
          l.length, (index) => DeviceGroup.fromJson(l[index]));
      rawGroups.addAll(add);
      cont = l.length == 9999;
    }

    List<DeviceGroup> groupsRepo = [];
    List<Future> futures = [];
    queryParameters.clear();
    queryParameters["filter_generic_duplicate_criteria"] = "true";
    for (int i = 0; i < rawGroups.length; i++) {
      if (rawGroups[i].auto_generated_by_device != null &&
          rawGroups[i].auto_generated_by_device != "") {
        continue;
      }
      final uri =
          '${Settings.getApiUrl() ?? 'localhost'}/device-repository/device-groups/${rawGroups[i].id}';
      futures.add(_dio!
          .get<dynamic>(uri,
              queryParameters: queryParameters,
              options: Options(headers: headers))
          .then((value) {
        if (value.data != null) {
          groupsRepo.add(DeviceGroup.fromJson(value.data));
        }
      }).catchError((e) {
        if (e.response?.statusCode == null || e.response!.statusCode! > 304) {
          throw UnexpectedStatusCodeException(
              e.response?.statusCode, "$uri ${e.message}");
        }
      }));
    }
    await Future.wait(futures);
    groupsRepo.forEach((element) async {
      element.favorite = await element.isFavorite();
    });
    if (isar != null && collection != null) {
      await isar!.writeTxn(() async {
        await collection.putAll(groupsRepo);
      });
    }

    return groupsRepo.map((e) => e.initImage()).toList(growable: false);
  }

  static Future<DeviceGroup> saveDeviceGroup(DeviceGroup group) async {
    _logger.d("Saving device group: ${group.id}");

    final uri =
        "${Settings.getApiUrl() ?? 'localhost'}/device-manager/device-groups/${group.id}?update-only-same-origin-attributes=$appOrigin";

    final encoded = json.encode(group.toJson());

    final headers = await Auth().getHeaders();
    await initOptions();
    final Response<Map<String, dynamic>> resp;
    try {
      resp = await _dio!.put<Map<String, dynamic>>(uri,
          options: Options(headers: headers), data: encoded);
    } on DioException catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 299) {
        throw UnexpectedStatusCodeException(
            e.response?.statusCode, "$uri ${e.message}");
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
    String uri =
        '${Settings.getApiUrl() ?? 'localhost'}/device-manager/device-groups/';

    final headers = await Auth().getHeaders();
    await initOptions();
    final dio = Dio()
      ..interceptors.add(DioCacheInterceptor(options: _options!))
      ..interceptors.add(ApiAvailableInterceptor())
      ..httpClientAdapter = AppHttpClientAdapter();
    final Response<dynamic> resp;
    try {
      resp = await dio.post<dynamic>(uri,
          options: Options(headers: headers),
          data: DeviceGroup("", name, [], "", [], []).toJson());
    } on DioException catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 299) {
        throw UnexpectedStatusCodeException(
            e.response?.statusCode, "$uri ${e.message}");
      }
      rethrow;
    }
    final savedGroup = DeviceGroup.fromJson(resp.data);
    if (isar != null) {
      await isar!.writeTxn(() async {
        await isar!.deviceGroups.put(savedGroup);
      });
    }

    return savedGroup.initImage();
  }

  static Future<void> deleteDeviceGroup(String id) async {
    String uri =
        '${Settings.getApiUrl() ?? 'localhost'}/device-manager/device-groups/$id';

    final headers = await Auth().getHeaders();
    await initOptions();
    final dio = Dio()
      ..interceptors.add(DioCacheInterceptor(options: _options!))
      ..interceptors.add(ApiAvailableInterceptor())
      ..httpClientAdapter = AppHttpClientAdapter();
    try {
      await dio.delete(uri, options: Options(headers: headers));
    } on DioException catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 299) {
        throw UnexpectedStatusCodeException(
            e.response?.statusCode, "$uri ${e.message}");
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

  static Future<DeviceGroupHelperResponse> getMatchingDevicesForGroup(
      List<String> deviceIds, int limit, int offset, String search) async {
    String uri =
        '${Settings.getApiUrl() ?? 'localhost'}/device-selection/device-group-helper';
    final Map<String, String> queryParameters = {};
    queryParameters["limit"] = limit.toString();
    queryParameters["offset"] = offset.toString();
    queryParameters["search"] = search;
    queryParameters["maintains_group_usability"] = "true";
    queryParameters["function_block_list"] =
        (dotenv.env["FUNCTION_GET_TIMESTAMP"] ?? "");

    final headers = await Auth().getHeaders();
    await initOptions();
    final Response<Map<String, dynamic>> resp;
    try {
      resp = await _dio!.post<Map<String, dynamic>>(uri,
          queryParameters: queryParameters,
          options: Options(headers: headers),
          data: json.encode(deviceIds));
    } on DioException catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 304) {
        throw UnexpectedStatusCodeException(
            e.response?.statusCode, "$uri ${e.message}");
      }
      rethrow;
    }
    if (resp.statusCode == 304) {
      _logger.d("Using cached device groups");
    }

    final instances = (resp.data as Map<String, dynamic>)["options"] ?? [];
    final criteria = (resp.data as Map<String, dynamic>)["criteria"] ?? [];
    return DeviceGroupHelperResponse(
        List<DeviceGroupCriteria>.generate(criteria.length,
            (index) => DeviceGroupCriteria.fromJson(criteria[index])),
        List<DeviceInstanceWithRemovesCriteria>.generate(instances.length,
            (index) {
          instances[index]["device"]["shared"] = false;
          instances[index]["device"]["creator"] = "";
          return DeviceInstanceWithRemovesCriteria(
              DeviceInstance.fromJson(instances[index]["device"]),
              (instances[index]["removes_criteria"] as List<dynamic>)
                  .isNotEmpty);
        }));
  }

  static bool isListAvailable() {
    String uri =
        '${Settings.getApiUrl() ?? 'localhost'}/device-repository/device-groups';
    return ApiAvailableService().isAvailable(uri);
  }

  static bool isCreateEditDeleteAvailable() {
    String uri =
        '${Settings.getApiUrl() ?? 'localhost'}/device-manager/device-groups';
    return ApiAvailableService().isAvailable(uri);
  }
}
