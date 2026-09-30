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
import 'package:mobile_app/shared/account_epoch.dart';
import 'package:mobile_app/shared/dio_status.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:isar_community/isar.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/services/settings.dart';

import 'package:mobile_app/exceptions/unexpected_status_code_exception.dart';
import 'package:mobile_app/models/attribute.dart';
import 'package:mobile_app/shared/dio_factory.dart';
import 'package:mobile_app/shared/isar.dart';
import 'package:mobile_app/shared/semaphore.dart';
import 'package:mobile_app/services/api_available.dart';
import 'package:mobile_app/services/auth.dart';

class DeviceGroupsService {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );


  static Future<List<Future<DeviceGroup>>> getDeviceGroups(
      {bool forceBackend = false}) async {
    final epoch = AccountEpoch.current;
    final collection = isar?.deviceGroups;

    if (!forceBackend && isar != null && collection != null) {
      final cached = await collection.where().sortByName().findAll();
      if (!Settings.getDeviceGroupsCachedWithAspectLists()) {
        for (final group in cached) {
          group.criteriaMayPredateAspectLists = true;
        }
      }
      return cached.map((e) => e.initImage()).toList();
    }

    String uri =
        '${Settings.getApiUrl() ?? 'localhost'}/device-repository/device-groups';
    final Map<String, String> queryParameters = {};
    queryParameters["limit"] = "9999";
    var cont = true;
    final rawGroups = <DeviceGroup>[];
    final headers = await Auth().getHeaders();
    final dio = await DioFactory.create(DioConfig.standard);
    while (cont) {
      queryParameters["offset"] = rawGroups.length.toString();
      final Response<List<dynamic>?> resp;
      try {
        resp = await dio.get<List<dynamic>?>(uri,
            queryParameters: queryParameters,
            options: Options(headers: headers));
      } on DioException catch (e) {
        checkReadStatus(e, uri);
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
    // One detail request per group, bounded: the shared client allows eight
    // connections per host, and an unbounded fan-out makes every request past
    // that queue against its own connect timeout — on a large account the tail
    // times out and takes the whole refresh down with it.
    final limiter = Semaphore(6);
    for (int i = 0; i < rawGroups.length; i++) {
      if (rawGroups[i].auto_generated_by_device != null &&
          rawGroups[i].auto_generated_by_device != "") {
        continue;
      }
      final uri =
          '${Settings.getApiUrl() ?? 'localhost'}/device-repository/device-groups/${rawGroups[i].id}';
      futures.add(limiter.withResource(() => dio
          .get<dynamic>(uri,
              queryParameters: queryParameters,
              options: Options(headers: headers))
          .then((value) {
        if (value.data != null) {
          groupsRepo.add(DeviceGroup.fromJson(value.data));
        }
      }).catchError((Object e) {
        // A tolerated status leaves this group out of the batch instead of
        // failing all of them, so nothing is rethrown here.
        if (e is! DioException) {
          throw UnexpectedStatusCodeException(null, "$uri $e");
        }
        checkReadStatus(e, uri);
      })));
    }
    await Future.wait(futures);
    if (isar != null && collection != null) {
      await AccountEpoch.writeIfCurrent(isar!, epoch, () async {
        await applyFavoriteMirror(groupsRepo);
        await collection.putAll(groupsRepo);
      });
    } else {
      await applyFavoriteMirror(groupsRepo);
    }

    return groupsRepo.map((e) => e.initImage()).toList(growable: false);
  }

  /// Sets the favorite mirror of [groups] from the per-account list, which is
  /// what a favorite is; the flag on the cached row only serves the Isar
  /// favorites query. Called inside the write that stores the rows, so a
  /// favorite tapped while the groups were loading is not overwritten. A row
  /// still counts until FavoritesMigration has moved what is on it.
  static Future<void> applyFavoriteMirror(List<DeviceGroup> groups) async {
    final favoriteIds = Settings.getFavoriteGroupIds();
    final Set<String> notYetMoved =
        isar != null && !Settings.getFavoritesMoved()
            ? (await isar!.deviceGroups
                    .where()
                    .favoriteEqualTo(true)
                    .idProperty()
                    .findAll())
                .toSet()
            : const {};
    for (final group in groups) {
      group.favorite =
          favoriteIds.contains(group.id) || notYetMoved.contains(group.id);
    }
  }

  /// Applies [change] to [group] and saves it. A group whose cached criteria
  /// may predate aspect lists is fetched fresh first and [change] applied to
  /// that copy, so its stale criteria never reach the backend; if the fetch
  /// fails, so does the save.
  static Future<DeviceGroup> saveDeviceGroup(DeviceGroup group, void Function(DeviceGroup group) change) async {
    _logger.d("Saving device group: ${group.id}");
    final epoch = AccountEpoch.current;
    change(group);
    if (group.criteriaMayPredateAspectLists) {
      group = await getDeviceGroup(group.id);
      change(group);
    }

    final uri =
        "${Settings.getApiUrl() ?? 'localhost'}/device-manager/device-groups/${group.id}?update-only-same-origin-attributes=$appOrigin";

    final encoded = json.encode(group.toJson());

    final headers = await Auth().getHeaders();
    final dio = await DioFactory.create(DioConfig.standard);
    final Response<Map<String, dynamic>> resp;
    try {
      resp = await dio.put<Map<String, dynamic>>(uri,
          options: Options(headers: headers), data: encoded);
    } on DioException catch (e) {
      checkWriteStatus(e, uri);
      rethrow;
    }

    final savedGroup = DeviceGroup.fromJson(resp.data!);
    // The response cannot carry the favorite - it lives in the per-account
    // list. Without this the cached row loses its mirror and the group drops
    // out of the favorites screen until the next fetch.
    savedGroup.favorite = Settings.getFavoriteGroupIds().contains(savedGroup.id);

    if (isar != null) {
      await AccountEpoch.writeIfCurrent(
          isar!, epoch, () => isar!.deviceGroups.put(savedGroup));
    }

    return savedGroup;
  }

  /// One device group as [getDeviceGroups] reads it from the backend.
  static Future<DeviceGroup> getDeviceGroup(String id) async {
    final uri = '${Settings.getApiUrl() ?? 'localhost'}/device-repository/device-groups/$id';
    final headers = await Auth().getHeaders();
    final dio = await DioFactory.create(DioConfig.standard);
    final Response<Map<String, dynamic>> resp;
    try {
      resp = await dio.get<Map<String, dynamic>>(uri,
          queryParameters: {"filter_generic_duplicate_criteria": "true"}, options: Options(headers: headers));
    } on DioException catch (e) {
      checkReadStatus(e, uri);
      rethrow;
    }
    final data = resp.data;
    if (data == null) throw UnexpectedStatusCodeException(resp.statusCode, "$uri returned no device group");
    return DeviceGroup.fromJson(data);
  }

  static Future<DeviceGroup> createDeviceGroup(String name) async {
    final epoch = AccountEpoch.current;
    String uri =
        '${Settings.getApiUrl() ?? 'localhost'}/device-manager/device-groups/';

    final headers = await Auth().getHeaders();
    final dio = await DioFactory.create(DioConfig.standard);
    final Response<dynamic> resp;
    try {
      resp = await dio.post<dynamic>(uri,
          options: Options(headers: headers),
          data: DeviceGroup("", name, [], "", [], []).toJson());
    } on DioException catch (e) {
      checkWriteStatus(e, uri);
      rethrow;
    }
    final savedGroup = DeviceGroup.fromJson(resp.data);
    if (isar != null) {
      await AccountEpoch.writeIfCurrent(
          isar!, epoch, () => isar!.deviceGroups.put(savedGroup));
    }

    return savedGroup.initImage();
  }

  static Future<void> deleteDeviceGroup(String id) async {
    String uri =
        '${Settings.getApiUrl() ?? 'localhost'}/device-manager/device-groups/$id';

    final headers = await Auth().getHeaders();
    final dio = await DioFactory.create(DioConfig.standard);
    try {
      await dio.delete(uri, options: Options(headers: headers));
    } on DioException catch (e) {
      checkWriteStatus(e, uri);
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
    final dio = await DioFactory.create(DioConfig.standard);
    final Response<Map<String, dynamic>> resp;
    try {
      resp = await dio.post<Map<String, dynamic>>(uri,
          queryParameters: queryParameters,
          options: Options(headers: headers),
          data: json.encode(deviceIds));
    } on DioException catch (e) {
      checkReadStatus(e, uri);
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
