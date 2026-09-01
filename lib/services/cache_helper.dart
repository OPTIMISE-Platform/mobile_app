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
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http_cache_hive_store/http_cache_hive_store.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/models/location.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/services/aspects.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/characteristics.dart';
import 'package:mobile_app/services/concepts.dart';
import 'package:mobile_app/services/device_classes.dart';
import 'package:mobile_app/services/device_groups.dart';
import 'package:mobile_app/services/device_types.dart';
import 'package:mobile_app/services/functions.dart';
import 'package:mobile_app/services/networks.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:path_provider/path_provider.dart';

import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/shared/isar.dart';
import 'package:mobile_app/shared/metadata_cache.dart';
import 'package:mobile_app/widgets/shared/toast.dart';
import 'package:mobile_app/services/devices.dart';
import 'package:mobile_app/services/locations.dart';

class CacheHelper {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  static String bodyCacheIDBuilder(RequestOptions request) {
    List<int> bytes = utf8.encode(request.method + request.uri.toString());
    if (request.data != null) {
      bytes = [...bytes, ...utf8.encode(request.data)];
    }
    return sha1.convert(bytes).toString();
  }

  static String newCacheKeyBuilder({
    required Uri url,
    Map<String, String>? headers,
    Object? body,
  }) {
    List<int> bytes = utf8.encode(url.toString());
    if (body != null) {
      bytes = [...bytes, ...utf8.encode(body.toString())];
    }
    return sha1.convert(bytes).toString();
  }

  static Future<String?> getCacheFile({String customSuffix = ""}) async {
    final dir = await getCacheDir();
    if (dir == null) {
      return null;
    }
    return "${dir.path}/cache${customSuffix}.box";
  }

  static Future<Directory?> getCacheDir() async {
    if (kIsWeb) {
      return null;
    }
    if (Platform.isAndroid) {
      List<Directory>? cacheDirs = await getExternalCacheDirectories();
      if (cacheDirs != null && cacheDirs.isNotEmpty) {
        return cacheDirs[0];
      }
    }

    return await getApplicationDocumentsDirectory();
  }

  static clearCache() async {
    final cacheFile = (await getCacheFile());
    await HiveCacheStore(cacheFile).clean();
    // The metadata byte cache lives in Isar, not Hive — without this the
    // metadata services keep serving their cached bytes for up to maxAge.
    await MetadataCache.clear();
    // Deliberately NOT cleared here: the Isar entity collections. They leak
    // the previous account's devices to the next account until the daily
    // refresh, but wiping them here destroys the favorites (which live only
    // on the Isar rows), kills the offline cache on any transient NotLoggedIn
    // auth event, and three services read the emptied collections as
    // authoritative. The account-switch leak needs a clear-on-account-change
    // at login instead.
  }

  /// [onProgress] reports the fraction of completed refresh tasks (0..1),
  /// one step per finished endpoint.
  ///
  /// [includeMetadata] warms the metadata caches alongside the Isar
  /// collections. A caller that reloads the in-memory metadata right after
  /// (settings refresh via [AppState.reloadMetadata]) passes false — the
  /// reload fetches against the cleared cache itself, and including the
  /// getters here would fetch and parse everything twice.
  static refreshCache({
    bool includeMetadata = true,
    void Function(double progress)? onProgress,
  }) async {
    if (isar == null) {
      return;
    }
    final tasks = <Future>[
      _refreshDevices(Duration.zero, reschedule: false),
      _refreshDeviceGroups(Duration.zero, reschedule: false),
      _refreshNetworks(Duration.zero, reschedule: false),
      _refreshLocations(Duration.zero, reschedule: false),
      if (includeMetadata) ...[
        FunctionsService.getFunctions(),
        AspectsService.getAspects(),
        ConceptsService.getConcepts(),
        CharacteristicsService.getCharacteristics(),
        DeviceTypesService.getDeviceTypes(),
        DeviceClassesService.getDeviceClasses(),
      ],
    ];
    var done = 0;
    await Future.wait(tasks.map((t) => t.whenComplete(() {
          done++;
          onProgress?.call(done / tasks.length);
        })));
  }

  static Future scheduleCacheUpdates() async {
    if (isar == null || !Auth().loggedIn || Settings.getLocalMode()) {
      return;
    }
    return await Future.wait([
      _scheduleRefreshDevices(),
      _scheduleRefreshDeviceGroups(),
      _scheduleRefreshNetworks(),
      _scheduleRefreshLocations(),
    ]);
  }

  static Future<void> _refreshDevices(Duration wait,
      {bool reschedule = true}) async {
    await Future.delayed(wait);
    var allDevicesLoaded = false;
    const limit = 5000;
    var deviceOffset = 0;
    DeviceInstance? last;
    final List<DeviceInstance> newDevices = [];

    while (!allDevicesLoaded) {
      try {
        newDevices.addAll((await DevicesService.getDevices(
            limit, deviceOffset, DeviceSearchFilter(""), last,
            forceBackend: true)).devices);
      } catch (e) {
        final err = "Could not get devices: $e";
        _logger.e(err);
        Toast.showToastNoContext(err);
        return;
      }
      allDevicesLoaded = newDevices.length < limit;
      deviceOffset = newDevices.length;
      last = newDevices.isNotEmpty ? newDevices.last : null;
    }

    if (isar != null) {
      // Write in chunks: serializing thousands of devices for Isar happens on
      // the calling (UI) isolate, so doing it in one putAll blocks frames right
      // after login. Awaiting between chunks lets the UI render in between. The
      // cache is briefly partial during the refresh, which only causes a cache
      // miss (backend fetch), never wrong data.
      const chunkSize = 500;
      await isar!.writeTxn(() => isar!.deviceInstances.clear());
      for (var i = 0; i < newDevices.length; i += chunkSize) {
        final end = i + chunkSize < newDevices.length
            ? i + chunkSize
            : newDevices.length;
        final chunk = newDevices.sublist(i, end);
        await isar!.writeTxn(() => isar!.deviceInstances.putAll(chunk));
      }
    }

    await Settings.setCacheUpdated("devices");
    if (reschedule) {
      _refreshDevices(const Duration(days: 1));
    }
  }

  static Future<void> _scheduleRefreshDevices() async {
    final dt = Settings.getCacheUpdated("devices");
    if (dt == null) {
      await _refreshDevices(Duration.zero);
    } else {
      final delay = dt.add(const Duration(days: 1)).difference(DateTime.now());
      if (delay.isNegative) {
        await _refreshDevices(delay);
      } else {
        _refreshDevices(delay);
      }
    }
  }

  static Future<void> _refreshDeviceGroups(Duration wait,
      {bool reschedule = true}) async {
    await Future.delayed(wait);
    late final List<DeviceGroup> deviceGroups;
    try {
      deviceGroups = await Future.wait(
          await DeviceGroupsService.getDeviceGroups(forceBackend: true));
    } catch (e) {
      final err = "Could not get deviceGroups: $e";
      _logger.e(err);
      Toast.showToastNoContext(err);
      return;
    }

    if (isar != null) {
      await isar!.writeTxn(() async {
        await isar!.deviceGroups.clear();
        await isar!.deviceGroups.putAll(deviceGroups);
      });
    }

    await Settings.setCacheUpdated("deviceGroups");
    if (reschedule) {
      _refreshDeviceGroups(const Duration(days: 1));
    }
  }

  static Future<void> _scheduleRefreshDeviceGroups() async {
    final dt = Settings.getCacheUpdated("deviceGroups");
    if (dt == null) {
      await _refreshDeviceGroups(Duration.zero);
    } else {
      final delay = dt.add(const Duration(days: 1)).difference(DateTime.now());
      if (delay.isNegative) {
        await _refreshDeviceGroups(delay);
      } else {
        _refreshDeviceGroups(delay);
      }
    }
  }

  static Future<void> _refreshNetworks(Duration wait,
      {bool reschedule = true}) async {
    if (isar == null) {
      return;
    }
    await Future.delayed(wait);
    late final List<Network> networks;

    try {
      networks = await NetworksService.getNetworks(null, true);
    } catch (e) {
      final err = "Could not get networks: $e";
      _logger.e(err);
      Toast.showToastNoContext(err);
      return;
    }

    if (isar != null) {
      await isar!.writeTxn(() async {
        await isar!.networks.clear();
        await isar!.networks.putAll(networks);
      });
    }

    await Settings.setCacheUpdated("networks");
    if (reschedule) {
      _refreshNetworks(const Duration(days: 1));
    }
  }

  static Future<void> _scheduleRefreshNetworks() async {
    final dt = Settings.getCacheUpdated("networks");
    if (dt == null) {
      await _refreshNetworks(Duration.zero);
    } else {
      final delay = dt.add(const Duration(days: 1)).difference(DateTime.now());
      if (delay.isNegative) {
        await _refreshNetworks(delay);
      } else {
        _refreshNetworks(delay);
      }
    }
  }

  static Future<void> _refreshLocations(Duration wait,
      {bool reschedule = true}) async {
    if (isar == null) {
      return;
    }
    await Future.delayed(wait);
    late final List<Location> locations;

    try {
      locations = await Future.wait(
          await LocationService.getLocations(forceBackend: true));
    } catch (e) {
      final err = "Could not get locations: $e";
      _logger.e(err);
      Toast.showToastNoContext(err);
      return;
    }

    if (isar != null) {
      await isar!.writeTxn(() async {
        await isar!.locations.clear();
        await isar!.locations.putAll(locations);
      });
    }

    await Settings.setCacheUpdated("locations");
    if (reschedule) {
      _refreshLocations(const Duration(days: 1));
    }
  }

  static Future<void> _scheduleRefreshLocations() async {
    final dt = Settings.getCacheUpdated("locations");
    if (dt == null) {
      await _refreshLocations(Duration.zero);
    } else {
      final delay = dt.add(const Duration(days: 1)).difference(DateTime.now());
      if (delay.isNegative) {
        await _refreshLocations(delay);
      } else {
        _refreshLocations(delay);
      }
    }
  }
}
