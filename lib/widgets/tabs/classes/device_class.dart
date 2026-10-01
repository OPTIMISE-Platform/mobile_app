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

import 'package:mobile_app/shared/devices_label.dart';
import 'dart:async';
import 'package:mobile_app/mixins/resume_refresh_mixin.dart';

import 'package:flutter/material.dart';
import 'package:mobile_app/services/haptic_feedback_proxy.dart';
import 'package:provider/provider.dart';

import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/models/device_class.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/shared/entity_leading_icon.dart';
import 'package:mobile_app/widgets/shared/grouped_list_tile.dart';
import 'package:mobile_app/widgets/shared/paged_device_list.dart';
import 'package:mobile_app/widgets/shared/sectioned_list_view.dart';
import 'package:mobile_app/widgets/tabs/device_tabs.dart';
import 'package:mobile_app/widgets/tabs/shared/device_list_item.dart';

class DeviceListByDeviceClass extends StatefulWidget {
  const DeviceListByDeviceClass({super.key});

  @override
  State<StatefulWidget> createState() => _DeviceListByDeviceClassState();
}

class _DeviceListByDeviceClassState extends State<DeviceListByDeviceClass> with ResumeRefreshMixin {
  /// The class whose devices are shown, by id: the list's order and length
  /// change as device types load.
  String? _selectedId;
  StreamSubscription? _refreshSubscription;

  @override
  void dispose() {
    _refreshSubscription?.cancel();
    super.dispose();
  }

  DeviceSearchFilter _selectedFilter() {
    final parentState = context.findAncestorStateOfType<State<DeviceTabs>>() as DeviceTabsState?;
    return parentState?.filter ?? DeviceSearchFilter("", deviceClassIds: [_selectedId!]);
  }

  @override
  void initState() {
    super.initState();
    // Resume and refreshes keep the classes, types and device index current
    // in AppState; only opening the tab without classes asks for a retry.
    if (AppState().deviceClasses.isEmpty) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => AppState().retryFailedMetadata());
    }
    _refreshSubscription = AppState().refreshPressed.listen((_) {
      if (mounted && _selectedId != null) {
        AppState().searchDevices(_selectedFilter(), true);
      }
    });
  }

  @override
  void onResumed() {
    if (_selectedId != null) AppState().searchDevices(_selectedFilter(), true);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, child) {
      final deviceClasses = state.usedDeviceClasses;
      final parentState = context.findAncestorStateOfType<State<DeviceTabs>>() as DeviceTabsState?;

      return Scrollbar(
        child: _selectedId == null
            // Both ends notify: init when it is done, a class load also when
            // it failed.
            ? deviceClasses.isEmpty && (!state.initialized || state.loadingDeviceClasses)
                ? const Center(child: DelayedCircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () async {
                      HapticFeedbackProxy.lightImpact();
                      state.reloadDeviceClasses();
                    },
                    child: deviceClasses.isEmpty
                        ? LayoutBuilder(
                            builder: (context, constraint) {
                              return SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(minHeight: constraint.maxHeight),
                                  child: const IntrinsicHeight(
                                    child: Column(
                                      children: [
                                        Expanded(
                                          child: Center(child: Text("No Classes")),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          )
                        : SectionedListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            sections: [
                              ListSection<DeviceClass>(
                                id: "classes",
                                items: deviceClasses,
                                keyOf: (deviceClass) => deviceClass.id,
                                itemBuilder: (_, deviceClass, position) {
                                  // Null until the device index is complete.
                                  final count = state.visibleDeviceCountOfClass(deviceClass.id);
                                  return GroupedListTile(
                                    position: position,
                                    child: ListTile(
                                        title: Text(deviceClass.name),
                                        subtitle: count == null ? null : Text(devicesLabel(count)),
                                        leading: EntityLeadingIcon(
                                            size: 48,
                                            fallbackIcon: Icons.devices,
                                            image: deviceClass.imageWidget),
                                        onTap: () {
                                          if (parentState != null) {
                                            parentState.filter = parentState.filter.copyWith(deviceClassIds: [deviceClass.id]);
                                          }
                                          state.searchDevices(parentState?.filter ?? DeviceSearchFilter("", deviceClassIds: [deviceClass.id]), true);
                                          parentState?.setState(() {
                                            parentState.setHideSearchOverride(false);
                                            parentState.onBackCallback = () {
                                              parentState.setState(() {
                                                parentState.filter = parentState.filter.without(deviceClassIds: true);
                                                parentState.customAppBarTitle = null;
                                                parentState.onBackCallback = null;
                                                parentState.setHideSearchOverride(null);
                                              });
                                              setState(() => _selectedId = null);
                                            };
                                            parentState.customAppBarTitle = deviceClass.name;
                                          });
                                          setState(() => _selectedId = deviceClass.id);
                                        }),
                                  );
                                },
                              ),
                            ],
                          ))
                : RefreshIndicator(
                    onRefresh: () async {
                      HapticFeedbackProxy.lightImpact();
                      state.searchDevices(_selectedFilter(), true);
                    },
                    child: PagedDeviceList(
                      source: DeviceSearchPages(state),
                      emptyText: "No Devices",
                      sections: [
                        ListSection<DeviceInstance>(
                          id: "devices",
                          items: state.devices,
                          keyOf: (device) => device.id,
                          itemBuilder: (_, device, position) =>
                              DeviceListItem(device, null, position: position),
                        ),
                      ],
                    )),
      );
    });
  }
}
