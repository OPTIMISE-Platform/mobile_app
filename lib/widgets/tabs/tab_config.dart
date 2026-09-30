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
  final OwnedFilter ownedFilter;

  const TabConfig({
    required this.index,
    required this.hideSearch,
    required this.showFabResolver,
    this.ownedFilter = OwnedFilter.none,
  });

  bool get showFab => showFabResolver();
}

enum OwnedFilter { none, location, group, network, deviceClass, favorites }

extension TabConfigExtension on TabConfig {
  /// [filter] without the field this tab "owns".
  DeviceSearchFilter withoutOwnedFilter(DeviceSearchFilter filter) {
    return switch (ownedFilter) {
      OwnedFilter.location => filter.without(locationIds: true),
      OwnedFilter.group => filter.without(deviceGroupIds: true),
      OwnedFilter.network => filter.without(networkIds: true),
      OwnedFilter.deviceClass => filter.without(deviceClassIds: true),
      OwnedFilter.favorites => filter.without(favorites: true),
      OwnedFilter.none => filter,
    };
  }

  bool ownsLocation() => ownedFilter == OwnedFilter.location;
  bool ownsGroup() => ownedFilter == OwnedFilter.group;
  bool ownsNetwork() => ownedFilter == OwnedFilter.network;
  bool ownsDeviceClass() => ownedFilter == OwnedFilter.deviceClass;
  bool ownsFavorites() => ownedFilter == OwnedFilter.favorites;
}

/// Registry of all tab configurations, keyed by tab index constant.
final Map<int, TabConfig> tabConfigs = {
  tabFavorites: TabConfig(
    index: tabFavorites,
    hideSearch: false,
    showFabResolver: () => false,
    ownedFilter: OwnedFilter.favorites,
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
    ownedFilter: OwnedFilter.location,
  ),
  tabGroups: const TabConfig(
    index: tabGroups,
    hideSearch: true,
    showFabResolver: DeviceGroupsService.isCreateEditDeleteAvailable,
    ownedFilter: OwnedFilter.group,
  ),
  tabNetworks: TabConfig(
    index: tabNetworks,
    hideSearch: true,
    showFabResolver: () => false,
    ownedFilter: OwnedFilter.network,
  ),
  tabClasses: TabConfig(
    index: tabClasses,
    hideSearch: true,
    showFabResolver: () => false,
    ownedFilter: OwnedFilter.deviceClass,
  ),
  tabSmartServices: TabConfig(
    index: tabSmartServices,
    hideSearch: true,
    showFabResolver: () => true,
  ),
  // FAB adds a sensor value; the page has its own device picker, so the
  // cross-tab device search doesn't apply.
  tabSensors: TabConfig(
    index: tabSensors,
    hideSearch: true,
    showFabResolver: () => true,
  ),
};