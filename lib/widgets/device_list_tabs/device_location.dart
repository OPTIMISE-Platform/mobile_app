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

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:mobile_app/widgets/device_list_tabs/device_list_item.dart';
import 'package:mobile_app/widgets/device_list_tabs/group_list_item.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/device_search_filter.dart';
import '../device_list.dart';

class DeviceListByLocation extends StatefulWidget {
  const DeviceListByLocation({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _DeviceListByLocationState();
}

class _DeviceListByLocationState extends State<DeviceListByLocation> {
  int? _selected;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, child) {
      final List<int> matchingGroups = [];
      if (_selected != null) {
        for (var i = 0; i < state.deviceGroups.length; i++) {
          if (state.locations[_selected!].device_group_ids.contains(state.deviceGroups[i].id)) {
            matchingGroups.add(i);
          }
        }
      }
      return Scrollbar(
        child: state.locations.isEmpty
            ? Center(child: PlatformCircularProgressIndicator())
            : _selected == null
                ? RefreshIndicator(
                    onRefresh: () => state.loadLocations(context),
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16.0),
                      itemCount: state.locations.length,
                      itemBuilder: (context, i) {
                        return Column(children: [
                          const Divider(),
                          ListTile(
                              title: Text(state.locations[i].name),
                              trailing: Container(
                                height: MediaQuery.of(context).textScaleFactor * 48,
                                width: MediaQuery.of(context).textScaleFactor * 48,
                                decoration: BoxDecoration(color: const Color(0xFF6c6c6c), borderRadius: BorderRadius.circular(50)),
                                child: Padding(
                                  padding: EdgeInsets.all(MediaQuery.of(context).textScaleFactor * 8),
                                  child: state.locations[i].imageWidget ?? Icon(PlatformIcons(context).location, color: Colors.white),
                                ),
                              ),
                              subtitle: Text(state.locations[i].device_ids.length.toString() +
                                  " Device" +
                                  (state.locations[i].device_ids.length > 1 ? "s" : "") +
                                  ", " +
                                  state.locations[i].device_group_ids.length.toString() +
                                  " Group" +
                                  (state.locations[i].device_group_ids.length > 1 ? "s" : "")),
                              onTap: () {
                                _loading = true;
                                state
                                    .searchDevices(DeviceSearchFilter("", null, state.locations[i].device_ids), context)
                                    .then((_) => setState(() => _loading = false));
                                final parentState = context.findAncestorStateOfType<State<DeviceList>>() as DeviceListState?;
                                parentState?.setState(() {
                                  parentState.onBackCallback = () {
                                    parentState.setState(() {
                                      parentState.customAppBarTitle = null;
                                      parentState.onBackCallback = null;
                                    });
                                    state.searchDevices(DeviceSearchFilter("", null, state.locations[i].device_ids), context);
                                    setState(() => _selected = null);
                                  };
                                  parentState.customAppBarTitle = state.locations[i].name;
                                });
                                setState(() {
                                  _selected = i;
                                });
                              })
                        ]);
                      },
                    ))
                : state.loadingDevices() || state.loadingDeviceGroups() || _loading
                    ? Center(
                        child: PlatformCircularProgressIndicator(),
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          _loading = true;
                          state
                              .searchDevices(DeviceSearchFilter("", null, state.locations[_selected!].device_ids), context, true)
                              .then((_) => setState(() => _loading = false));
                        },
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16.0),
                          itemCount: state.totalDevices + matchingGroups.length,
                          itemBuilder: (_, i) {
                            if (i > state.devices.length + matchingGroups.length - 1) {
                              return const SizedBox.shrink();
                            }
                            if (i < state.devices.length) {
                              return Column(
                                children: [const Divider(), DeviceListItem(i, null)],
                              );
                            }
                            return Column(
                              children: [
                                const Divider(),
                                GroupListItem(matchingGroups.elementAt(i - state.devices.length),
                                    (_) => state.searchDevices(DeviceSearchFilter("", null, state.locations[_selected!].device_ids), context))
                              ],
                            );
                          },
                        )),
      );
    });
  }
}
