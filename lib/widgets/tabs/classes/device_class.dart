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
import 'package:mobile_app/widgets/shared/entity_leading_circle.dart';
import 'package:mobile_app/widgets/shared/grouped_list_tile.dart';
import 'package:mobile_app/widgets/shared/scrollable_empty_state.dart';
import 'package:mobile_app/widgets/shared/sectioned_list_view.dart';
import 'package:mobile_app/widgets/tabs/device_tabs.dart';
import 'package:mobile_app/widgets/tabs/shared/device_list_item.dart';

class DeviceListByDeviceClass extends StatefulWidget {
  const DeviceListByDeviceClass({super.key});

  @override
  State<StatefulWidget> createState() => _DeviceListByDeviceClassState();
}

class _DeviceListByDeviceClassState extends State<DeviceListByDeviceClass> with ResumeRefreshMixin {
  int? _selected;
  StreamSubscription? _refreshSubscription;

  @override
  void dispose() {
    _refreshSubscription?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final parentState = context.findAncestorStateOfType<State<DeviceTabs>>() as DeviceTabsState?;
    _refreshSubscription = AppState().refreshPressed.listen((_) {
      if (_selected == null) {
        AppState().loadDeviceClasses();
      } else if (parentState != null) {
        AppState().searchDevices(
            parentState.filter, true);
      }
    });
  }

  @override
  void onResumed() {
    if (_selected == null) {
      AppState().loadDeviceClasses();
    } else {
      final deviceClasses = AppState().deviceClasses.values.toList(growable: false);
      final parentState = context.findAncestorStateOfType<State<DeviceTabs>>() as DeviceTabsState?;
      AppState().searchDevices(parentState?.filter ?? DeviceSearchFilter("", [deviceClasses[_selected!].id]), true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, child) {
      final deviceClasses = state.deviceClasses.values.toList(growable: false);
      final parentState = context.findAncestorStateOfType<State<DeviceTabs>>() as DeviceTabsState?;

      return Scrollbar(
        child: state.loadingDeviceClasses
            ? const Center(child: DelayedCircularProgressIndicator())
            : _selected == null
                ? RefreshIndicator(
                    onRefresh: () async {
                      HapticFeedbackProxy.lightImpact();
                      state.loadDeviceClasses();
                    },
                    child: state.deviceClasses.isEmpty
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
                                  return GroupedListTile(
                                    position: position,
                                    child: ListTile(
                                        title: Text(deviceClass.name),
                                        subtitle: Text(
                                            "${deviceClass.deviceIds.length} Device${deviceClass.deviceIds.length > 1 || deviceClass.deviceIds.isEmpty ? "s" : ""}"),
                                        leading: EntityLeadingCircle(
                                            size: 48,
                                            fallbackIcon: Icons.devices,
                                            image: deviceClass.imageWidget),
                                        onTap: () {
                                          parentState?.filter.deviceClassIds = [deviceClass.id];
                                          state.searchDevices(parentState?.filter ?? DeviceSearchFilter("", [deviceClass.id]), true);
                                          parentState?.setState(() {
                                            parentState.setHideSearchOverride(false);
                                            parentState.onBackCallback = () {
                                              parentState.setState(() {
                                                parentState.filter.deviceClassIds = null;
                                                parentState.customAppBarTitle = null;
                                                parentState.onBackCallback = null;
                                                parentState.setHideSearchOverride(null);
                                              });
                                              setState(() => _selected = null);
                                            };
                                            parentState.customAppBarTitle = deviceClass.name;

                                            setState(() {
                                              _selected = deviceClasses.indexOf(deviceClass);
                                            });
                                          });
                                        }),
                                  );
                                },
                              ),
                            ],
                          ))
                : RefreshIndicator(
                    onRefresh: () async {
                      HapticFeedbackProxy.lightImpact();
                      state.searchDevices(parentState?.filter ?? DeviceSearchFilter("", [deviceClasses[_selected!].id]), true);
                    },
                    child: state.devices.isEmpty && state.devicesListEnded
                        ? const ScrollableEmptyState("No Devices")
                        : SectionedListView(
                            sections: [
                              ListSection<DeviceInstance>(
                                id: "devices",
                                items: state.devices,
                                keyOf: (device) => device.id,
                                itemBuilder: (_, device, position) =>
                                    DeviceListItem(device, null,
                                        position: position),
                              ),
                            ],
                            trailing: [
                              if (state.devicesListItemCount >
                                  state.devices.length)
                                Builder(builder: (_) {
                                  state.loadDevices();
                                  return const SizedBox.shrink();
                                }),
                            ],
                    )),
      );
    });
  }
}
