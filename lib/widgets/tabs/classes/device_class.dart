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

import 'package:flutter/material.dart';
import 'package:mobile_app/services/haptic_feedback_proxy.dart';
import 'package:provider/provider.dart';

import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/tabs/device_tabs.dart';
import 'package:mobile_app/widgets/tabs/shared/device_list_item.dart';

class DeviceListByDeviceClass extends StatefulWidget {
  const DeviceListByDeviceClass({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _DeviceListByDeviceClassState();
}

class _DeviceListByDeviceClassState extends State<DeviceListByDeviceClass> with WidgetsBindingObserver {
  int? _selected;
  StreamSubscription? _refreshSubscription;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshSubscription?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final parentState = context.findAncestorStateOfType<State<DeviceTabs>>() as DeviceTabsState?;
    _refreshSubscription = AppState().refreshPressed.listen((_) {
      if (_selected == null) {
        AppState().loadDeviceClasses();
      } else if (parentState != null) {
        AppState().searchDevices(
            parentState.filter, context, true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && ModalRoute.of(context)?.isCurrent == true) {
      if (_selected == null) {
        AppState().loadDeviceClasses();
      } else {
        final deviceClasses = AppState().deviceClasses.values.toList(growable: false);
        final parentState = context.findAncestorStateOfType<State<DeviceTabs>>() as DeviceTabsState?;
        AppState().searchDevices(parentState?.filter ?? DeviceSearchFilter("", [deviceClasses[_selected!].id]), context, true);
      }
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
                                  child: IntrinsicHeight(
                                    child: Column(
                                      children: const [
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
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: MyTheme.inset,
                            itemCount: deviceClasses.length,
                            itemBuilder: (context, i) {
                              return Column(children: [
                                i > 0 ? const Divider() : const SizedBox.shrink(),
                                ListTile(
                                    title: Text(deviceClasses[i].name),
                                    subtitle: Text(
                                        "${deviceClasses[i].deviceIds.length} Device${deviceClasses[i].deviceIds.length > 1 || deviceClasses[i].deviceIds.isEmpty ? "s" : ""}"),
                                    leading: Container(
                                      height: MediaQuery.of(context).textScaleFactor * 48,
                                      width: MediaQuery.of(context).textScaleFactor * 48,
                                      decoration: BoxDecoration(color: const Color(0xFF6c6c6c), borderRadius: BorderRadius.circular(50)),
                                      child: Padding(
                                        padding: EdgeInsets.all(MediaQuery.of(context).textScaleFactor * 8),
                                        child: deviceClasses[i].imageWidget ?? const Icon(Icons.devices, color: Colors.white),
                                      ),
                                    ),
                                    onTap: () {
                                      parentState?.filter.deviceClassIds = [deviceClasses[i].id];
                                      state.searchDevices(parentState?.filter ?? DeviceSearchFilter("", [deviceClasses[i].id]), context, true);
                                      parentState?.setState(() {
                                        parentState.hideSearch = false;
                                        parentState.onBackCallback = () {
                                          parentState.setState(() {
                                            parentState.filter.deviceClassIds = null;
                                            parentState.customAppBarTitle = null;
                                            parentState.onBackCallback = null;
                                            parentState.hideSearch = true;
                                          });
                                          setState(() => _selected = null);
                                        };
                                        parentState.customAppBarTitle = deviceClasses[i].name;

                                        setState(() {
                                          _selected = i;
                                        });
                                      });
                                    })
                              ]);
                            },
                          ))
                : RefreshIndicator(
                    onRefresh: () async {
                      HapticFeedbackProxy.lightImpact();
                      state.searchDevices(parentState?.filter ?? DeviceSearchFilter("", [deviceClasses[_selected!].id]), context, true);
                    },
                    child: ListView.builder(
                      padding: MyTheme.inset,
                      itemCount: state.totalDevices,
                      itemBuilder: (_, i) {
                        if (i >= state.devices.length) {
                          state.loadDevices(context);
                          return const SizedBox.shrink();
                        }
                        final List<Widget> children = [];
                        if (i>0) {
                          children.add(const Divider());
                        }
                        children.add(DeviceListItem(state.devices[i], null));
                        return Column(
                          children: children,
                        );
                      },
                    )),
      );
    });
  }
}
