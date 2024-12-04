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

import 'package:isar/isar.dart';
import 'package:mobile_app/app_state.dart';

import 'package:mobile_app/models/device_instance.dart';

class DeviceSearchFilter {
  String query;
  List<String>? deviceClassIds;
  List<String>? deviceIds;
  List<String>? deviceGroupIds;
  List<String>? locationIds;
  List<String>? networkIds;
  bool? favorites;

  DeviceSearchFilter(this.query, [this.deviceClassIds, this.deviceIds, this.networkIds, this.deviceGroupIds, this.locationIds, this.favorites]);

  static DeviceSearchFilter empty() {
    return DeviceSearchFilter("");
  }

  DeviceSearchFilter clone() {
    return DeviceSearchFilter(query, deviceClassIds, deviceIds, networkIds, deviceGroupIds, locationIds, favorites);
  }

  List<String> _add(List<String>? l, String id) {
    l ??= [];
    if (!l.contains(id)) l.add(id);
    return l;
  }

  List<String>? _remove(List<String>? l, String id) {
    l?.remove(id);
    if (l != null && l.isEmpty) {
      l = null;
    }
    return l;
  }

  addDeviceClass(String id) => deviceClassIds = _add(deviceClassIds, id);

  removeDeviceClass(String id) => deviceClassIds = _remove(deviceClassIds, id);

  addDeviceGroup(String id) => deviceGroupIds = _add(deviceGroupIds, id);

  removeDeviceGroup(String id) => deviceGroupIds = _remove(deviceGroupIds, id);

  addLocation(String id) => locationIds = _add(locationIds, id);

  removeLocation(String id) => locationIds = _remove(locationIds, id);

  addNetwork(String id) => networkIds = _add(networkIds, id);

  removeNetwork(String id) => networkIds = _remove(networkIds, id);

  Map<String, String> toQueryParams(int limit, int offset, DeviceInstance? lastDevice, [List<String>? ids]) {
    final queryParameters = <String, String>{};
    queryParameters["limit"] = limit.toString();
    queryParameters["offset"] = offset.toString();
    queryParameters["sort"] = "display_name.asc";
    queryParameters["search"] = query;

    if (ids != null) {
      queryParameters["ids"] = ids.join(",");
    }

    List<String>? allDeviceIds;
    if ((allDeviceIds = _allDeviceIds) != null) {
      final ids = (queryParameters["ids"] ?? "").split(",");
      ids.addAll(allDeviceIds!);
      queryParameters["ids"] = ids.join(",");
    }

    if (networkIds != null) {
      final List<String> localIds = [];
      AppState().networks.where((element) => networkIds!.contains(element.id))
          .forEach((element) =>
          localIds.addAll(element.device_local_ids ?? []));
      queryParameters["local_ids"] = localIds.join(",");
    }

    if (favorites == true) {
      queryParameters["attr-keys"] = attributeFavorite;
    }
    return queryParameters;
  }

  QueryBuilder<DeviceInstance, DeviceInstance, QAfterLimit> isarQuery(int limit, int offset, IsarCollection<DeviceInstance> collection) {
    var isarQ = collection.filter().display_nameContains(query, caseSensitive: false);

    List<String>? allDeviceIds;
    if ((allDeviceIds = _allDeviceIds) != null) {
      isarQ = isarQ.anyOf(allDeviceIds!, (q, String e) => q.idEqualTo(e));
    }

    if (networkIds != null) {
      final List<String> localIds = [];
      AppState().networks.where((element) => networkIds!.contains(element.id)).forEach((element) => localIds.addAll(element.device_local_ids ?? []));
      isarQ =  isarQ.anyOf(localIds, (q, String e) => q.local_idEqualTo(e));
    }

    if (favorites == true) {
      isarQ = isarQ.favoriteEqualTo(true);
    }

    return isarQ.sortByDisplay_name().offset(offset).limit(limit);
  }

  List<String>? get _allDeviceIds {
    List<String>? allDeviceIds;
    if (deviceIds != null) {
      allDeviceIds = deviceIds?.toList();
    }

    if (deviceClassIds != null) {
      final List<String> deviceIds = [];
      for (var e in deviceClassIds!) {
        deviceIds.addAll(AppState().deviceClasses[e]?.deviceIds ?? []);
      }
      if (allDeviceIds == null) {
        allDeviceIds = deviceIds;
      } else {
        allDeviceIds = allDeviceIds.where((element) => deviceIds.contains(element)).toList();
      }
    }

    if (deviceGroupIds != null) {
      final List<String> devicesInGroups = [];
      AppState().deviceGroups.where((element) => deviceGroupIds!.contains(element.id)).forEach((group) => devicesInGroups.addAll(group.device_ids));
      if (allDeviceIds == null) {
        allDeviceIds = devicesInGroups;
      } else {
        allDeviceIds = allDeviceIds.where((element) => devicesInGroups.contains(element)).toList();
      }
    }

    if (locationIds != null) {
      final List<String> deviceInLocations = [];
      AppState().locations.where((element) => locationIds!.contains(element.id)).forEach((location) => deviceInLocations.addAll(location.device_ids));
      if (allDeviceIds == null) {
        allDeviceIds = deviceInLocations;
      } else {
        allDeviceIds = allDeviceIds.where((element) => deviceInLocations.contains(element)).toList();
      }
    }
    return allDeviceIds;
  }

  @override
  String toString() {
    return (query +
        deviceClassIds.toString() +
        deviceIds.toString() +
        networkIds.toString() +
        deviceGroupIds.toString() +
        favorites.toString() +
        locationIds.toString());
  }

  @override
  int get hashCode {
    return toString().hashCode;
  }

  @override
  bool operator ==(Object other) {
    if (other is! DeviceSearchFilter) {
      return false;
    }
    return hashCode == other.hashCode;
  }
}
