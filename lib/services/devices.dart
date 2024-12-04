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
import 'package:isar/isar.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/api_available_interceptor.dart';

import 'package:mobile_app/exceptions/unexpected_status_code_exception.dart';
import 'package:mobile_app/models/attribute.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/shared/http_client_adapter.dart';
import 'package:mobile_app/shared/isar.dart';
import 'package:mobile_app/services/api_available.dart';
import 'package:mobile_app/services/auth.dart';

class DeviceInstanceWithTotal {
  final List<DeviceInstance> devices;
  final int total;

  DeviceInstanceWithTotal(this.devices, this.total);
}

class DevicesService {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  static Dio? _dio;
  static CacheOptions? _options;
  static String? _cacheFile;

  static initOptions() async {
    _cacheFile ??= await CacheHelper.getCacheFile();
    _options ??= CacheOptions(
      store: HiveCacheStore(_cacheFile),
      hitCacheOnErrorExcept: [401, 403],
      priority: CachePriority.normal,
      allowPostMethod: true,
      keyBuilder: CacheHelper.bodyCacheIDBuilder,
    );
    _dio ??= Dio(BaseOptions(
        connectTimeout: const Duration(milliseconds: 1500),
        sendTimeout: const Duration(milliseconds: 5000),
        receiveTimeout: const Duration(milliseconds: 5000),))
      ..interceptors.add(DioCacheInterceptor(options: _options!))
      ..interceptors.add(ApiAvailableInterceptor())
      ..httpClientAdapter = AppHttpClientAdapter();
  }

  static Future<DeviceInstanceWithTotal> getDevices(int limit, int offset,
      DeviceSearchFilter filter, DeviceInstance? lastDevice,
      {bool forceBackend = false}) async {
    final start = DateTime.now();
    await initOptions();

    final collection = isar?.collection<DeviceInstance>();

    if (!forceBackend && isar != null && collection != null &&
        await collection.count() >= AppState().totalDevices) {
      final devices = await filter.isarQuery(limit, offset, collection)
          .build()
          .findAll();
      _logger.d("Getting devices from local DB took ${DateTime.now().difference(
          start)}");
      return DeviceInstanceWithTotal(devices, devices.length);
    }
    final headers = await Auth().getHeaders();

    final queryParameters = filter.toQueryParams(limit, offset, lastDevice);
    final uri = '${Settings.getApiUrl() ??
        'localhost'}/device-repository/extended-devices';
    _logger.d("Devices: $queryParameters");
    final Response<List<dynamic>?> resp;
    try {
      final DateTime start = DateTime.now();
      resp = await _dio!.get<List<dynamic>?>(
          uri, options: Options(headers: headers), queryParameters: queryParameters,);
      _logger.d("getDevices ${DateTime.now().difference(start)}");
    } on DioException catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 304) {
        throw UnexpectedStatusCodeException(
            e.response?.statusCode, "$uri ${e.message}");
      }
      rethrow;
    }

    if (resp.statusCode == 304) {
      _logger.d("Using cached devices");
    }
    
    final total = int.parse(resp.headers.value('X-Total-Count') ?? "0");

    final l = resp.data ?? [];
    final devices = List<DeviceInstance>.generate(
        l.length, (index) => DeviceInstance.fromJson(l[index]));
    _logger.d("Getting devices from remote DB took ${DateTime.now().difference(
        start)}");


    List<Future> futures = [];
    devices.forEach((element) {  futures.add(element.isFavorite().then((value) => element.favorite = value));});
    await Future.wait(futures);

    if (isar != null && collection != null) {
      await isar!.writeTxn(() async {
        await collection.putAll(devices);
      });
    }
    return DeviceInstanceWithTotal(devices, total);
  }

  static Future<void> saveDevice(DeviceInstance device) async {
    _logger.d("Saving device: ${device.id}");

    final uri =
        "${Settings.getApiUrl() ?? 'localhost'}/device-manager/devices/${device
        .id}?update-only-same-origin-attributes=$sharedOrigin,$appOrigin";

    final encoded = json.encode(device.toJson());

    final headers = await Auth().getHeaders();
    await initOptions();
    try {
      await _dio!.put<dynamic>(
          uri, options: Options(headers: headers), data: encoded);
    } on DioException catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 299) {
        throw UnexpectedStatusCodeException(
            e.response?.statusCode, "$uri ${e.message}");
      }
      rethrow;
    }

    if (isar != null) {
      await isar!.writeTxn(() async {
        await isar!.collection<DeviceInstance>().put(device);
      });
    }
    return;
  }

  static bool isListAvailable() {
    String uri = '${Settings.getApiUrl() ?? 'localhost'}/device-repository/extended-devices';
    return ApiAvailableService().isAvailable(uri);
  }

  static bool isSaveAvailable() {
    final uri =
        "${Settings.getApiUrl() ?? 'localhost'}/device-manager/devices";
    return ApiAvailableService().isAvailable(uri);
  }

}
