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
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/services/haptic_feedback_proxy.dart';
import 'package:mobile_app/widgets/tabs/favorites/favorites_controller.dart';
import 'package:provider/provider.dart';

import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
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
    with WidgetsBindingObserver {
  final GlobalKey _keyFavButton = GlobalKey();

  late DeviceListFavoritesController controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final state = context.read<AppState>();
    controller = DeviceListFavoritesController(state);
    controller.init(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ModalRoute.of(context)?.isCurrent == true) {
      controller.onResume(context);
    }
  }

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
            state.refreshDevices(context);
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
                child: PlatformElevatedButton(
                  widgetKey: _keyFavButton,
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
    return ListView.builder(
      padding: MyTheme.inset,
      itemCount: devices.length + groups.length,
      itemBuilder: (_, i) {
        if (i < devices.length) {
          return Column(
            children: [
              if (i > 0) const Divider(),
              DeviceListItem(devices[i], null),
            ],
          );
        }

        final group = groups[i - devices.length];

        return Column(
          children: [
            const Divider(),
            GroupListItem(group, (_) {
              final parent = context
                  .findAncestorStateOfType<State<DeviceTabs>>()
              as DeviceTabsState?;

              if (parent == null) return;

              parent.filter.deviceGroupIds = null;
              state.searchDevices(parent.filter, context);
            }),
          ],
        );
      },
    );
  }
}