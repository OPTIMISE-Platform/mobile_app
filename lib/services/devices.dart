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
import 'package:isar_community/isar.dart';
import 'package:mobile_app/shared/chunked_parse.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_instance.dart';
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
    // Uncached dio: device responses are persisted in Isar, so the Hive HTTP
    // cache was redundant — and reading the (up to 5000) cached device response
    // back through Hive ran a CRC32 over it on the UI isolate, blocking input
    // right after login (the background cache refresh).
    _dio ??= await DioFactory.create(DioConfig.standard);
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

    if (!forceBackend && isar != null && collection != null) {
      final cachedCount = await collection.count();
      // An empty cache is never "complete": right after a fresh login both
      // cachedCount and totalDevices are 0, which this shortcut used to read as
      // cache-complete — answering every query with an empty list until the
      // first full cache refresh finished.
      if (cachedCount > 0 && cachedCount >= AppState().totalDevices) {
        final devices = await filter
            .isarQuery(limit, offset, collection)
            .build()
            .findAll();
        _logger.d(
          "Getting devices from local DB took ${DateTime.now().difference(start)}",
        );
        return DeviceInstanceWithTotal(devices, cachedCount);
      }
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
    // Parse in chunks that yield to the event loop. A 5000-device cache refresh
    // otherwise blocks the UI isolate in one stretch (right after login), and
    // compute() only trades that block for an equally-blocking copy-in/out of
    // thousands of objects across the isolate boundary.
    final devices = await parseListChunked(l, DeviceInstance.fromJson);
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
