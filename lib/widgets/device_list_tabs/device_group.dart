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
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/widgets/device_list_tabs/device_list_item.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../device_page.dart';

class DeviceGroupList extends StatefulWidget {
  const DeviceGroupList({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _DeviceGroupListState();
}

class _DeviceGroupListState extends State<DeviceGroupList> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, child) {
      return state.deviceGroups.isEmpty
          ? state.loadingDeviceGroups()
              ? Center(child: PlatformCircularProgressIndicator())
              : const Center(child: Text("No Groups"))
          : _selected == null
              ? RefreshIndicator(
                  onRefresh: () => state.loadDeviceGroups(context),
                  child: Scrollbar(
                      child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16.0),
                    itemCount: state.deviceGroups.length,
                    itemBuilder: (context, i) {
                      return Column(children: [
                        const Divider(),
                        ListTile(
                            title: Text(state.deviceGroups[i].name),
                            trailing: Container(
                              height: MediaQuery.of(context).textScaleFactor * 48,
                              width: MediaQuery.of(context).textScaleFactor * 48,
                              decoration: BoxDecoration(color: const Color(0xFF6c6c6c), borderRadius: BorderRadius.circular(50)),
                              child: Padding(
                                  padding: EdgeInsets.all(MediaQuery.of(context).textScaleFactor * 8),
                                  child: state.deviceGroups[i].imageWidget ?? const Icon(Icons.devices_other, color: Colors.white)),
                            ),
                            onTap: () async {
                              await state.searchDevices(DeviceSearchFilter("", null, state.deviceGroups[i].device_ids), context);
                              Navigator.push(
                                  context,
                                  platformPageRoute(
                                    context: context,
                                    builder: (context) {
                                      final target = DevicePage(null, i);
                                      target.refresh(context, state);
                                      return target;
                                    },
                                  ));
                            })
                      ]);
                    },
                  )))
              : state.devices.isEmpty
                  ? state.loadingDevices()
                      ? Center(
                          child: PlatformCircularProgressIndicator(),
                        )
                      : const Center(child: Text("No Devices"))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16.0),
                      itemCount: state.totalDevices,
                      itemBuilder: (_, i) {
                        if (i > state.devices.length - 1) {
                          return const SizedBox.shrink();
                        }
                        return Column(
                          children: [const Divider(), DeviceListItem(i, null)],
                        );
                      },
                    );
    });
  }
}
