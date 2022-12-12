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
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/services/cache_helper.dart';

import '../exceptions/unexpected_status_code_exception.dart';
import '../models/attribute.dart';
import '../models/device_search_filter.dart';
import '../shared/http_client_adapter.dart';
import '../shared/isar.dart';
import 'auth.dart';

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
    _dio ??= Dio(BaseOptions(connectTimeout: 1500, sendTimeout: 5000, receiveTimeout: 5000))
      ..interceptors.add(DioCacheInterceptor(options: _options!))
      ..httpClientAdapter = AppHttpClientAdapter();
  }

  static Future<List<DeviceInstance>> getDevices(int limit, int offset, DeviceSearchFilter filter, DeviceInstance? lastDevice, {bool forceBackend = false}) async {
    final start = DateTime.now();
    await initOptions();

    final collection =  isar.collection<DeviceInstance>();

    if (!forceBackend && await collection.count() >= AppState().totalDevices) {
      final devices = await filter.isarQuery(limit, offset, collection).build().findAll();
      _logger.d("Getting devices from local DB took ${DateTime.now().difference(start)}");
      Future.delayed(const Duration(seconds: 2), () async {
        final refreshDeviceIds = devices.where((element) => element.network?.localService == null).map((e) => e.id).toList(growable: false);
        if (refreshDeviceIds.isEmpty) {
          return;
        }
        final refreshFilter =  DeviceSearchFilter("");
        refreshFilter.deviceIds = refreshDeviceIds;
        final refreshedDevices = await getDevices(refreshDeviceIds.length, 0, refreshFilter, null, forceBackend: true);
        refreshedDevices.forEach((d1) {
          final i = AppState().devices.indexWhere((d2) => d1.id == d2.id);
          if (i == -1) return;
          AppState().devices[i] = d1;
        });
        await isar.writeTxn(() async {
          await collection.putAll(refreshedDevices);
        });
      });
      return devices;
    }
    final headers = await Auth().getHeaders();

    final body = filter.toBody(limit, offset, lastDevice);
    final uri = '${dotenv.env["API_URL"] ?? 'localhost'}/permissions/query/v3/query';
    final encoded = json.encode(body);
    _logger.d("Devices: $encoded");
    final Response<List<dynamic>?> resp;
    try {
      final DateTime start = DateTime.now();
      resp = await _dio!.post<List<dynamic>?>(uri, options: Options(headers: headers), data: encoded);
      _logger.d("getDevices ${DateTime.now().difference(start)}");
    } on DioError catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 304) {
        throw UnexpectedStatusCodeException(e.response?.statusCode);
      }
      rethrow;
    }

    if (resp.statusCode == 304) {
      _logger.d("Using cached devices");
    }

    final l = resp.data ?? [];
    final devices = List<DeviceInstance>.generate(l.length, (index) => DeviceInstance.fromJson(l[index]));
    _logger.d("Getting devices from remote DB took ${DateTime.now().difference(start)}");

    await isar.writeTxn(() async {
      await collection.putAll(devices);
    });
    return devices;
  }

  static Future<void> saveDevice(DeviceInstance device) async {
    _logger.d("Saving device: ${device.id}");

    final uri =
        "${dotenv.env["API_URL"] ?? 'localhost'}/device-manager/devices/${device.id}?update-only-same-origin-attributes=$sharedOrigin,$appOrigin";

    final encoded = json.encode(device.toJson());

    final headers = await Auth().getHeaders();
    await initOptions();
    try {
      await _dio!.put<dynamic>(uri, options: Options(headers: headers), data: encoded);
    } on DioError catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 299) {
        throw UnexpectedStatusCodeException(e.response?.statusCode);
      }
      rethrow;
    }

    await isar.writeTxn(() async {
      await isar.collection<DeviceInstance>().put(device);
    });
    return;
  }

  /// Only returns an upper limit of devices, which only respects the filter.query and no further filters
  static Future<int> getTotalDevices(DeviceSearchFilter filter) async {
    String uri = '${dotenv.env["API_URL"] ?? 'localhost'}/permissions/query/v3/total/devices';

    final Map<String, String> queryParameters = {};
    if (filter.query.isNotEmpty) {
      queryParameters["search"] = filter.query;
    }
    final headers = await Auth().getHeaders();
    await initOptions();
    final Response<int> resp;
    try {
      final DateTime start = DateTime.now();
      resp = await _dio!.get<int>(uri, options: Options(headers: headers), queryParameters: queryParameters);
      _logger.d("getTotalDevices ${DateTime.now().difference(start)}");
    } on DioError catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 304) {
        throw UnexpectedStatusCodeException(e.response?.statusCode);
      }
      rethrow;
    }

    if (resp.statusCode == 304) {
      _logger.d("Using cached total devices");
    }

    return resp.data ?? 0;
  }
}
