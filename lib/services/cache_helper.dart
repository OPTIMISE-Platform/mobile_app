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
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/services/device_groups.dart';
import 'package:mobile_app/services/networks.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:path_provider/path_provider.dart';

import '../models/device_instance.dart';
import '../shared/isar.dart';
import 'devices.dart';

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
    HiveCacheStore(cacheFile).clean();
    if (isar != null) {
      await isar!.writeTxn(() async {
        await isar!.clear();
      });
    }
  }

  static refreshCache() async {
    if (isar == null) {
      return;
    }
    await Future.wait([_refreshDevices(Duration.zero, reschedule: false), _refreshDeviceGroups(Duration.zero, reschedule: false), _refreshNetworks(Duration.zero, reschedule: false)]);
  }

  static scheduleCacheUpdates() {
    if (isar == null) {
      return;
    }
    _scheduleRefreshDevices();
    _scheduleRefreshDeviceGroups();
    _scheduleRefreshNetworks();
  }

  static Future<void> _refreshDevices(Duration wait, {bool reschedule = true}) async {
    await Future.delayed(wait);
    var allDevicesLoaded = false;
    var deviceOffset = 0;
    DeviceInstance? last;

    if (isar != null) {
      await isar!.writeTxn(() async {
        await isar!.deviceInstances.clear();
      });
    }
    while (!allDevicesLoaded) {
      late final List<DeviceInstance> newDevices;
      const limit = 5000;
      try {
        newDevices = await DevicesService.getDevices(limit, deviceOffset, DeviceSearchFilter(""), last, forceBackend: true);
      } catch (e) {
        _logger.e("Could not get devices: $e");
        return;
      }
      allDevicesLoaded = newDevices.length < limit;
      deviceOffset += newDevices.length;
      last = newDevices.isNotEmpty ? newDevices.last : null;
    }
    await Settings.setCacheUpdated("devices");
    if (reschedule) {
      _refreshDevices(const Duration(days: 1));
    }
  }

  static _scheduleRefreshDevices() {
    final dt = Settings.getCacheUpdated("devices");
    if (dt == null) {
      _refreshDevices(Duration.zero);
    } else {
      _refreshDevices(dt.add(const Duration(days: 1)).difference(DateTime.now()));
    }
  }

  static Future<void> _refreshDeviceGroups(Duration wait, {bool reschedule = true}) async {
    await Future.delayed(wait);

    if (isar != null) {
      await isar!.writeTxn(() async {
        await isar!.deviceGroups.clear();
      });
    }

    try {
      await DeviceGroupsService.getDeviceGroups(forceBackend: true);
    } catch (e) {
      _logger.e("Could not get deviceGroups: $e");
      return;
    }

    await Settings.setCacheUpdated("deviceGroups");
    if (reschedule) {
      _refreshDeviceGroups(const Duration(days: 1));
    }
  }

  static _scheduleRefreshDeviceGroups() {
    final dt = Settings.getCacheUpdated("deviceGroups");
    if (dt == null) {
      _refreshDeviceGroups(Duration.zero);
    } else {
      _refreshDeviceGroups(dt.add(const Duration(days: 1)).difference(DateTime.now()));
    }
  }

  static Future<void> _refreshNetworks(Duration wait, {bool reschedule = true}) async {
    if (isar == null) {
      return;
    }
    await Future.delayed(wait);

    if (isar != null) {
      await isar!.writeTxn(() async {
        await isar!.networks.clear();
      });
    }

    try {
      await NetworksService.getNetworks(null, true);
    } catch (e) {
      _logger.e("Could not get networks: $e");
      return;
    }

    await Settings.setCacheUpdated("networks");
    if (reschedule) {
      _refreshDeviceGroups(const Duration(days: 1));
    }
  }

  static _scheduleRefreshNetworks() {
    final dt = Settings.getCacheUpdated("networks");
    if (dt == null) {
      _refreshNetworks(Duration.zero);
    } else {
      _refreshNetworks(dt.add(const Duration(days: 1)).difference(DateTime.now()));
    }
  }
}
