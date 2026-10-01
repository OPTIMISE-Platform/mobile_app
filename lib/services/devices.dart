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
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:mobile_app/shared/account_epoch.dart';
import 'package:mobile_app/shared/dio_status.dart';
import 'package:isar_community/isar.dart';
import 'package:mobile_app/shared/chunked_parse.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/models/attribute.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/shared/dio_factory.dart';
import 'package:mobile_app/shared/isar.dart';
import 'package:mobile_app/services/api_available.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/services/auth.dart';

/// See [DevicesService.getCachedDeviceIndex].
typedef CachedDeviceIndex = ({
  Map<String, String> deviceTypes,
  Set<String> inactive,
  bool complete,
});

class DeviceInstanceWithTotal {
  final List<DeviceInstance> devices;
  final int total;

  /// Whether the devices were read from the local cache, whose connection
  /// states may be stale, rather than from the platform.
  final bool fromCache;

  DeviceInstanceWithTotal(this.devices, this.total, {this.fromCache = false});
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
    bool store = true,
  }) async {
    final start = DateTime.now();
    final epoch = AccountEpoch.current;
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
        AppState().noteDevices(devices);
        return DeviceInstanceWithTotal(devices, cachedCount, fromCache: true);
      }
    }
    final headers = await Auth().getHeaders();

    final queryParameters = filter.toQueryParams(limit, offset, lastDevice);
    if (filter.favorites == true && (queryParameters["ids"] ?? "").isEmpty) {
      // A favorites filter that narrowed to nothing is answerable here: the
      // list is local, and an empty ids matches nothing on the backend too.
      return DeviceInstanceWithTotal([], 0);
    }
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
      checkReadStatus(e, uri);
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

    // Without [store] the caller stores and indexes the devices itself. The
    // mirror is set inside the write, so a star tapped meanwhile is kept.
    var mirrored = false;
    if (store) {
      if (isar != null && collection != null) {
        mirrored = await AccountEpoch.writeIfCurrent(isar!, epoch, () async {
          await applyFavoriteMirror(devices);
          await collection.putAll(devices);
        });
      }
      if (epoch == AccountEpoch.current) AppState().noteDevices(devices);
    }
    if (!mirrored) await applyFavoriteMirror(devices);
    return DeviceInstanceWithTotal(devices, total);
  }

  /// Sets the `favorite` mirror of [devices] from the per-account list. The
  /// device refresh calls it inside each chunk's write, so a star tapped since
  /// the fetch is not overwritten.
  static Future<void> applyFavoriteMirror(List<DeviceInstance> devices) async {
    // Favorites live in their own per-account list, not on these rows, so they
    // survive the row being replaced (and the whole cache being dropped).
    final favoriteIds = Settings.getFavoriteDeviceIds();
    // Until FavoritesMigration has run, the rows are still the only record of
    // the favorites made before the changeover. Clearing their flag here would
    // destroy them before the migration ever gets to read them - the refresh
    // that runs right after a login would be enough.
    final Set<String> notYetMoved =
        isar != null && !Settings.getFavoritesMoved()
            ? (await isar!.deviceInstances
                    .where()
                    .favoriteEqualTo(true)
                    .idProperty()
                    .findAll())
                .toSet()
            : const {};
    for (final element in devices) {
      element.favorite =
          favoriteIds.contains(element.id) || notYetMoved.contains(element.id);
    }
  }

  /// The cached devices as the device index needs them: each one's type, the
  /// ids of those that are inactive, and whether a full device refresh has
  /// filled the cache, without which its rows are only the pages seen so far.
  /// The attribute is judged by [DeviceInstance.isInactive], which trims and
  /// ignores case.
  static Future<CachedDeviceIndex> getCachedDeviceIndex() async {
    final db = isar;
    if (db == null) {
      return (deviceTypes: <String, String>{}, inactive: <String>{}, complete: false);
    }
    final complete = CacheHelper.devicesRefreshedOnce();
    // One read transaction, so the two property lists come from the same rows
    // in the same order.
    return db.txn(() async {
      final ids = await db.deviceInstances.where().idProperty().findAll();
      final types =
          await db.deviceInstances.where().device_type_idProperty().findAll();
      if (ids.length != types.length) {
        throw StateError("device index read ${ids.length} ids and "
            "${types.length} types");
      }
      final inactiveRows = await db.deviceInstances
          .filter()
          .attributesElement((a) => a.keyEqualTo(attributeInactive))
          .findAll();
      return (
        deviceTypes: {for (var i = 0; i < ids.length; i++) ids[i]: types[i]},
        inactive: {for (final d in inactiveRows) if (d.isInactive) d.id},
        complete: complete,
      );
    });
  }

  /// The devices with the given [ids], fetched in requests of at most 50 ids
  /// each so the query string stays bounded. Ids the backend does not know are
  /// missing from the result.
  static Future<List<DeviceInstance>> getDevicesByIds(List<String> ids) async {
    const chunk = 50;
    final result = <DeviceInstance>[];
    for (var i = 0; i < ids.length; i += chunk) {
      final part = ids.sublist(i, min(i + chunk, ids.length));
      final filter = DeviceSearchFilter('', deviceIds: part);
      result.addAll((await getDevices(part.length, 0, filter, null)).devices);
    }
    return result;
  }

  static Future<void> saveDevice(DeviceInstance device) async {
    _logger.d("Saving device: ${device.id}");
    final epoch = AccountEpoch.current;

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
      checkWriteStatus(e, uri);
      rethrow;
    }

    if (isar != null) {
      await AccountEpoch.writeIfCurrent(
          isar!, epoch, () => isar!.collection<DeviceInstance>().put(device));
    }
    if (epoch == AccountEpoch.current) AppState().noteDevices([device]);
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
