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
import 'package:dio_cache_interceptor_hive_store/dio_cache_interceptor_hive_store.dart';
import 'package:flutter/foundation.dart';
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
import 'package:mobile_app/services/device_types_perm_search.dart';
import 'package:mobile_app/services/functions.dart';
import 'package:mobile_app/services/networks.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:path_provider/path_provider.dart';

import '../models/device_instance.dart';
import '../shared/isar.dart';
import '../widgets/shared/toast.dart';
import 'devices.dart';
import 'locations.dart';

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
    if (isar != null) {
      await isar!.writeTxn(() async {
        await isar!.clear();
      });
    }
    return await Future.delayed(const Duration(seconds: 1));
  }

  static refreshCache() async {
    if (isar == null) {
      return;
    }
    await Future.wait([
      _refreshDevices(Duration.zero, reschedule: false),
      _refreshDeviceGroups(Duration.zero, reschedule: false),
      _refreshNetworks(Duration.zero, reschedule: false),
      _refreshLocations(Duration.zero, reschedule: false),
      FunctionsService.getNestedFunctions(),
      AspectsService.getAspects(),
      ConceptsService.getConcepts(),
      CharacteristicsService.getCharacteristics(),
      DeviceTypesPermSearchService.getDeviceTypes(),
      DeviceClassesService.getDeviceClasses(),
    ]);
  }

  static Future scheduleCacheUpdates() async {
    if (isar == null || !Auth().loggedIn) {
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
    final Map<String, int> deviceTypeIds = {};

    while (!allDevicesLoaded) {
      try {
        newDevices.addAll(await DevicesService.getDevices(
            limit, deviceOffset, DeviceSearchFilter(""), last,
            forceBackend: true));
      } catch (e) {
        final err = "Could not get devices: $e";
        _logger.e(err);
        Toast.showToastNoContext(err);
        return;
      }
      allDevicesLoaded = newDevices.length < limit;
      deviceOffset = newDevices.length;
      last = newDevices.isNotEmpty ? newDevices.last : null;

      newDevices.forEach((element) =>
      deviceTypeIds[element.device_type_id] = 0);
      if (isar != null) {
        await isar!.writeTxn(() async {
          await isar!.deviceInstances.clear();
          await isar!.deviceInstances.putAll(newDevices);
        });
      }
    }
    final List<Future> futures = [];
    deviceTypeIds.keys.forEach((element) => futures.add(DeviceTypesService.getDeviceType(element)));
    await Future.wait(futures);
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
