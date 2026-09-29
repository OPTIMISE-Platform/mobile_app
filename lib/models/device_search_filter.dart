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

import 'package:isar_community/isar.dart';
import 'package:mobile_app/app_state.dart';

import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/services/settings.dart';

class DeviceSearchFilter {
  String query;
  List<String>? deviceClassIds;
  List<String>? deviceIds;
  List<String>? deviceGroupIds;
  List<String>? locationIds;
  List<String>? networkIds;
  bool? favorites;

  /// Whether devices carrying the `inactive` attribute are included. Off by
  /// default; not persisted, the same as the other filter fields here.
  bool showInactive;

  /// A null id list places no constraint, an empty one matches nothing. Lists
  /// are copied and unmodifiable.
  DeviceSearchFilter(
    this.query, {
    List<String>? deviceClassIds,
    List<String>? deviceIds,
    List<String>? deviceGroupIds,
    List<String>? locationIds,
    List<String>? networkIds,
    this.favorites,
    this.showInactive = false,
  })  : deviceClassIds = _frozen(deviceClassIds),
        deviceIds = _frozen(deviceIds),
        deviceGroupIds = _frozen(deviceGroupIds),
        locationIds = _frozen(locationIds),
        networkIds = _frozen(networkIds);

  static DeviceSearchFilter empty() {
    return DeviceSearchFilter("");
  }

  /// AppState keeps its own copy: the tabs still change their filter in place.
  DeviceSearchFilter clone() => copyWith();

  /// A copy with the given fields replaced; a null argument keeps the field.
  /// Use [without] to clear one to null.
  DeviceSearchFilter copyWith({
    String? query,
    List<String>? deviceClassIds,
    List<String>? deviceIds,
    List<String>? deviceGroupIds,
    List<String>? locationIds,
    List<String>? networkIds,
    bool? favorites,
    bool? showInactive,
  }) {
    return DeviceSearchFilter(
      query ?? this.query,
      deviceClassIds: deviceClassIds ?? this.deviceClassIds,
      deviceIds: deviceIds ?? this.deviceIds,
      deviceGroupIds: deviceGroupIds ?? this.deviceGroupIds,
      locationIds: locationIds ?? this.locationIds,
      networkIds: networkIds ?? this.networkIds,
      favorites: favorites ?? this.favorites,
      showInactive: showInactive ?? this.showInactive,
    );
  }

  /// A copy with every field flagged true cleared to null.
  DeviceSearchFilter without({
    bool deviceClassIds = false,
    bool deviceIds = false,
    bool deviceGroupIds = false,
    bool locationIds = false,
    bool networkIds = false,
    bool favorites = false,
  }) {
    return DeviceSearchFilter(
      query,
      deviceClassIds: deviceClassIds ? null : this.deviceClassIds,
      deviceIds: deviceIds ? null : this.deviceIds,
      deviceGroupIds: deviceGroupIds ? null : this.deviceGroupIds,
      locationIds: locationIds ? null : this.locationIds,
      networkIds: networkIds ? null : this.networkIds,
      favorites: favorites ? null : this.favorites,
      showInactive: showInactive,
    );
  }

  static List<String>? _frozen(List<String>? l) =>
      l == null ? null : List.unmodifiable(l);

  static List<String> _with(List<String>? l, String id) =>
      l != null && l.contains(id) ? l : [...?l, id];

  /// Null once the last id is gone, so the field stops constraining.
  static List<String>? _without(List<String>? l, String id) {
    if (l == null) return null;
    final rest = l.where((e) => e != id).toList();
    return rest.isEmpty ? null : rest;
  }

  DeviceSearchFilter withDeviceClass(String id) =>
      copyWith(deviceClassIds: _with(deviceClassIds, id));

  DeviceSearchFilter withoutDeviceClass(String id) {
    final rest = _without(deviceClassIds, id);
    return rest == null ? without(deviceClassIds: true) : copyWith(deviceClassIds: rest);
  }

  DeviceSearchFilter withDeviceGroup(String id) =>
      copyWith(deviceGroupIds: _with(deviceGroupIds, id));

  DeviceSearchFilter withoutDeviceGroup(String id) {
    final rest = _without(deviceGroupIds, id);
    return rest == null ? without(deviceGroupIds: true) : copyWith(deviceGroupIds: rest);
  }

  DeviceSearchFilter withLocation(String id) =>
      copyWith(locationIds: _with(locationIds, id));

  DeviceSearchFilter withoutLocation(String id) {
    final rest = _without(locationIds, id);
    return rest == null ? without(locationIds: true) : copyWith(locationIds: rest);
  }

  DeviceSearchFilter withNetwork(String id) =>
      copyWith(networkIds: _with(networkIds, id));

  DeviceSearchFilter withoutNetwork(String id) {
    final rest = _without(networkIds, id);
    return rest == null ? without(networkIds: true) : copyWith(networkIds: rest);
  }

  addDeviceClass(String id) => deviceClassIds = withDeviceClass(id).deviceClassIds;

  removeDeviceClass(String id) => deviceClassIds = withoutDeviceClass(id).deviceClassIds;

  addDeviceGroup(String id) => deviceGroupIds = withDeviceGroup(id).deviceGroupIds;

  removeDeviceGroup(String id) => deviceGroupIds = withoutDeviceGroup(id).deviceGroupIds;

  addLocation(String id) => locationIds = withLocation(id).locationIds;

  removeLocation(String id) => locationIds = withoutLocation(id).locationIds;

  addNetwork(String id) => networkIds = withNetwork(id).networkIds;

  removeNetwork(String id) => networkIds = withoutNetwork(id).networkIds;

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
      // Favorites are a local, per-account id list, so narrow by id. The
      // previous attr-keys query asked for a device attribute that nothing
      // writes and therefore always came back empty.
      final favoriteIds = Settings.getFavoriteDeviceIds();
      final existing = queryParameters["ids"];
      queryParameters["ids"] = (existing == null || existing.isEmpty
              ? favoriteIds
              : favoriteIds.intersection(existing.split(",").toSet()))
          .join(",");
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
    return "DeviceSearchFilter(query: $query, deviceClassIds: $deviceClassIds, "
        "deviceIds: $deviceIds, deviceGroupIds: $deviceGroupIds, "
        "locationIds: $locationIds, networkIds: $networkIds, "
        "favorites: $favorites, showInactive: $showInactive)";
  }

  // Id lists compare as sets: every query built from them is a membership
  // test, so order and duplicates never change the result.
  static bool _sameIds(List<String>? a, List<String>? b) {
    if (a == null || b == null) return a == b;
    final setA = a.toSet();
    final setB = b.toSet();
    return setA.length == setB.length && setA.containsAll(setB);
  }

  static int _idsHash(List<String>? l) =>
      l == null ? null.hashCode : Object.hashAllUnordered(l.toSet());

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is DeviceSearchFilter &&
            other.query == query &&
            _sameIds(other.deviceClassIds, deviceClassIds) &&
            _sameIds(other.deviceIds, deviceIds) &&
            _sameIds(other.deviceGroupIds, deviceGroupIds) &&
            _sameIds(other.locationIds, locationIds) &&
            _sameIds(other.networkIds, networkIds) &&
            other.favorites == favorites &&
            other.showInactive == showInactive;
  }

  @override
  int get hashCode => Object.hash(
        query,
        _idsHash(deviceClassIds),
        _idsHash(deviceIds),
        _idsHash(deviceGroupIds),
        _idsHash(locationIds),
        _idsHash(networkIds),
        favorites,
        showInactive,
      );
}
