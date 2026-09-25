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

import 'package:flutter/material.dart';
import 'package:mobile_app/mixins/resume_refresh_mixin.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/services/haptic_feedback_proxy.dart';
import 'package:mobile_app/widgets/tabs/favorites/favorites_controller.dart';
import 'package:provider/provider.dart';

import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/shared/section_list_header.dart';
import 'package:mobile_app/widgets/shared/slice_position.dart';
import 'package:mobile_app/widgets/tabs/device_tabs.dart';
import 'package:mobile_app/widgets/tabs/shared/device_list_item.dart';
import 'package:mobile_app/widgets/tabs/shared/group_list_item.dart';

import '../nav.dart';

class DeviceListFavorites extends StatefulWidget {
  const DeviceListFavorites({super.key});

  @override
  State<DeviceListFavorites> createState() => _DeviceListFavoritesState();
}

class _DeviceListFavoritesState extends State<DeviceListFavorites>
    with ResumeRefreshMixin {
  final GlobalKey _keyFavButton = GlobalKey();

  // Nullable: created once in didChangeDependencies. A late field here made
  // dispose/lifecycle throw LateInitializationError when creation failed.
  DeviceListFavoritesController? controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Once: didChangeDependencies re-fires on theme/MediaQuery changes, and a
    // fresh controller each time leaked the previous one's refresh listener.
    if (controller != null) return;
    final state = context.read<AppState>();
    controller = DeviceListFavoritesController(state)..init(context);
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  void onResumed() => controller?.onResume(context);

  void _openDeviceListView(BuildContext context) {
    final parentState =
        context.findAncestorStateOfType<State<DeviceTabs>>()
            as DeviceTabsState?;

    parentState?.switchScreen(tabDevices, true);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        final matchingGroups =
        state.deviceGroups.where((g) => g.favorite).toList();

        final devices =
        state.devices.where((d) => d.favorite).toList();

        Widget content;

        if (state.loadingDevices || !state.favoritesDataLoaded) {
          // Until the first devices *and* groups load completes, an empty
          // favorites list just means "not loaded yet" — show the spinner
          // instead of flashing the "Add Favorites" empty state.
          content = const Center(
            child: DelayedCircularProgressIndicator(),
          );
        } else if (devices.isEmpty && matchingGroups.isEmpty) {
          content = _buildEmptyState(context);
        } else {
          content = _buildList(state, devices, matchingGroups);
        }

        return RefreshIndicator(
          onRefresh: () async {
            HapticFeedbackProxy.lightImpact();
            state.refreshDevices();
          },
          child: Scrollbar(child: content),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: LayoutBuilder(
        builder: (context, constraint) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraint.maxHeight),
              child: Center(
                child: ElevatedButton(
                  key: _keyFavButton,
                  child: const Text("Add Favorites"),
                  onPressed: () => _openDeviceListView(context),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildList(AppState state,
      List<DeviceInstance> devices,
      List<DeviceGroup> groups,) {
    // Both kinds get their own section header only when both are present -
    // a favorites list of just devices (the common case) stays one section.
    final sectioned = devices.isNotEmpty && groups.isNotEmpty;
    final headerCount = sectioned ? 2 : 0;

    GroupListItem groupItem(int i) => GroupListItem(groups[i], (_) {
          final parent = context.findAncestorStateOfType<State<DeviceTabs>>()
              as DeviceTabsState?;

          if (parent == null) return;

          parent.filter.deviceGroupIds = null;
          state.searchDevices(parent.filter);
        },
            key: ValueKey("group-${groups[i].id}"),
            position: SlicePosition.forIndex(i, groups.length));

    return ListView.builder(
      padding: Spacing.listPadding(context),
      itemCount: devices.length + groups.length + headerCount,
      itemBuilder: (_, i) {
        if (sectioned) {
          if (i == 0) return const SectionListHeader("Devices");
          i -= 1;
          if (i < devices.length) {
            return DeviceListItem(devices[i], null,
                key: ValueKey("device-${devices[i].id}"),
                position: SlicePosition.forIndex(i, devices.length));
          }
          i -= devices.length;
          if (i == 0) return const SectionListHeader("Groups");
          return groupItem(i - 1);
        }

        if (i < devices.length) {
          return DeviceListItem(devices[i], null,
              key: ValueKey("device-${devices[i].id}"),
              position: SlicePosition.forIndex(i, devices.length));
        }
        return groupItem(i - devices.length);
      },
      // A row's key always names its device/group, so its State (an
      // expanded/transitioning DeviceListItem) stays with it when the
      // section headers appear or disappear and shift every index after.
      findChildIndexCallback: (key) {
        final id = (key as ValueKey<String>).value;
        if (id.startsWith("device-")) {
          final deviceId = id.substring("device-".length);
          final index = devices.indexWhere((d) => d.id == deviceId);
          if (index == -1) return null;
          return sectioned ? index + 1 : index;
        }
        final groupId = id.substring("group-".length);
        final index = groups.indexWhere((g) => g.id == groupId);
        if (index == -1) return null;
        return sectioned ? devices.length + 2 + index : devices.length + index;
      },
    );
  }
}