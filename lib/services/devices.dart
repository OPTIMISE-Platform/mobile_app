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
import 'package:flutter/foundation.dart';
import 'package:http_cache_hive_store/http_cache_hive_store.dart';import 'package:isar_community/isar.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/exceptions/unexpected_status_code_exception.dart';
import 'package:mobile_app/models/attribute.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/shared/dio_factory.dart';
import 'package:mobile_app/shared/isar.dart';
import 'package:mobile_app/services/api_available.dart';
import 'package:mobile_app/services/auth.dart';

class DeviceInstanceWithTotal {
  final List<DeviceInstance> devices;
  final int total;

  DeviceInstanceWithTotal(this.devices, this.total);
}

class DevicesService {
  static final _logger = Logger(printer: SimplePrinter());

  static Dio? _dio;

  static initOptions() async {
    _dio ??= await DioFactory.create(DioConfig.cached7);
  }

  static Future<DeviceInstanceWithTotal> getDevices(
    int limit,
    int offset,
    DeviceSearchFilter filter,
    DeviceInstance? lastDevice, {
    bool forceBackend = false,
  }) async {
    final start = DateTime.now();
    await initOptions();

    final collection = isar?.collection<DeviceInstance>();

    if (!forceBackend &&
        isar != null &&
        collection != null &&
        await collection.count() >= AppState().totalDevices) {
      final devices = await filter
          .isarQuery(limit, offset, collection)
          .build()
          .findAll();
      _logger.d(
        "Getting devices from local DB took ${DateTime.now().difference(start)}",
      );
      return DeviceInstanceWithTotal(devices, await collection.count());
    }
    final headers = await Auth().getHeaders();

    final queryParameters = filter.toQueryParams(limit, offset, lastDevice);
    final uri =
        '${Settings.getApiUrl() ?? 'localhost'}/device-repository/extended-devices';
    //_logger.d("Devices: $queryParameters");
    final Response<List<dynamic>?> resp;
    try {
      final DateTime start = DateTime.now();
      resp = await _dio!.get<List<dynamic>?>(
        uri,
        options: Options(headers: headers),
        queryParameters: queryParameters,
      );
      _logger.d("getDevices ${DateTime.now().difference(start)}");
    } on DioException catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 304) {
        throw UnexpectedStatusCodeException(
          e.response?.statusCode,
          "$uri ${e.message}",
        );
      }
      rethrow;
    }

    if (resp.statusCode == 304) {
      _logger.d("Using cached devices");
    }

    final total = int.parse(resp.headers.value('X-Total-Count') ?? "0");

    final l = resp.data ?? [];
    // Large pages (e.g. the 5000-device cache refresh) are parsed off the UI
    // thread; DeviceInstance.fromJson is pure now (network is resolved lazily
    // via a getter) so it is isolate-safe. Small interactive pages are parsed
    // inline — the isolate spawn would cost more than the work itself.
    final devices = l.length > _isolateParseThreshold
        ? await compute(_parseDeviceInstances, l)
        : _parseDeviceInstances(l);
    _logger.d(
      "Getting devices from remote DB took ${DateTime.now().difference(start)}",
    );

    // Fetch all favorite ids in a single query instead of one isFavorite()
    // lookup per device. With limit=5000 (cache refresh) that was up to 5000
    // separate Isar queries on the UI thread, freezing the loading spinner.
    if (isar != null) {
      final favoriteIds = (await isar!.deviceInstances
              .where()
              .favoriteEqualTo(true)
              .idProperty()
              .findAll())
          .toSet();
      for (final element in devices) {
        element.favorite = favoriteIds.contains(element.id);
      }
    }

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
        "${Settings.getApiUrl() ?? 'localhost'}/device-manager/devices/${device.id}?update-only-same-origin-attributes=$sharedOrigin,$appOrigin";

    final encoded = json.encode(device.toJson());

    final headers = await Auth().getHeaders();
    await initOptions();
    try {
      await _dio!.put<dynamic>(
        uri,
        options: Options(headers: headers),
        data: encoded,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == null || e.response!.statusCode! > 299) {
        throw UnexpectedStatusCodeException(
          e.response?.statusCode,
          "$uri ${e.message}",
        );
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
    String uri =
        '${Settings.getApiUrl() ?? 'localhost'}/device-repository/extended-devices';
    return ApiAvailableService().isAvailable(uri);
  }

  static bool isSaveAvailable() {
    final uri = "${Settings.getApiUrl() ?? 'localhost'}/device-manager/devices";
    return ApiAvailableService().isAvailable(uri);
  }
}

/// Above this many devices in one response, parsing is moved to an isolate.
const _isolateParseThreshold = 500;

List<DeviceInstance> _parseDeviceInstances(List<dynamic> l) =>
    List<DeviceInstance>.generate(
        l.length, (index) => DeviceInstance.fromJson(l[index]));
