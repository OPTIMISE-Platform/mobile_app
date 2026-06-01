/*
 * Copyright 2026 InfAI (CC SES)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */

import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/services/device_groups.dart';
import 'package:mobile_app/services/locations.dart';
import 'package:mobile_app/widgets/tabs/nav.dart';

/// Declarative configuration for each navigation tab.
/// Add new tabs here instead of editing switch statements.
class TabConfig {
  final int index;
  final bool hideSearch;
  final bool Function() showFabResolver;

  /// Which filter field this tab "owns" — cleared when leaving, excluded from
  /// the cross-tab filter count, and not reset by the Reset action.
  final _OwnedFilter ownedFilter;

  const TabConfig({
    required this.index,
    required this.hideSearch,
    required this.showFabResolver,
    this.ownedFilter = _OwnedFilter.none,
  });

  bool get showFab => showFabResolver();
}

enum _OwnedFilter { none, location, group, network, deviceClass, favorites }

extension TabConfigExtension on TabConfig {
  /// Clear only the filter this tab "owns" from [filter].
  void clearOwnedFilter(DeviceSearchFilter filter) {
    switch (ownedFilter) {
      case _OwnedFilter.location:
        filter.locationIds = null;
        break;
      case _OwnedFilter.group:
        filter.deviceGroupIds = null;
        break;
      case _OwnedFilter.network:
        filter.networkIds = null;
        break;
      case _OwnedFilter.deviceClass:
        filter.deviceClassIds = null;
        break;
      case _OwnedFilter.favorites:
        filter.favorites = null;
        break;
      case _OwnedFilter.none:
        break;
    }
  }

  bool ownsLocation() => ownedFilter == _OwnedFilter.location;
  bool ownsGroup() => ownedFilter == _OwnedFilter.group;
  bool ownsNetwork() => ownedFilter == _OwnedFilter.network;
  bool ownsDeviceClass() => ownedFilter == _OwnedFilter.deviceClass;
  bool ownsFavorites() => ownedFilter == _OwnedFilter.favorites;
}

/// Registry of all tab configurations, keyed by tab index constant.
final Map<int, TabConfig> tabConfigs = {
  tabFavorites: TabConfig(
    index: tabFavorites,
    hideSearch: false,
    showFabResolver: () => false,
    ownedFilter: _OwnedFilter.favorites,
  ),
  tabDashboard: TabConfig(
    index: tabDashboard,
    hideSearch: true,
    showFabResolver: () => false,
  ),
  tabDevices: TabConfig(
    index: tabDevices,
    hideSearch: false,
    showFabResolver: () => false,
  ),
  tabLocations: const TabConfig(
    index: tabLocations,
    hideSearch: true,
    showFabResolver: LocationService.isCreateEditDeleteAvailable,
    ownedFilter: _OwnedFilter.location,
  ),
  tabGroups: const TabConfig(
    index: tabGroups,
    hideSearch: true,
    showFabResolver: DeviceGroupsService.isCreateEditDeleteAvailable,
    ownedFilter: _OwnedFilter.group,
  ),
  tabNetworks: TabConfig(
    index: tabNetworks,
    hideSearch: true,
    showFabResolver: () => false,
    ownedFilter: _OwnedFilter.network,
  ),
  tabClasses: TabConfig(
    index: tabClasses,
    hideSearch: true,
    showFabResolver: () => false,
    ownedFilter: _OwnedFilter.deviceClass,
  ),
  tabSmartServices: TabConfig(
    index: tabSmartServices,
    hideSearch: true,
    showFabResolver: () => true,
  ),
};