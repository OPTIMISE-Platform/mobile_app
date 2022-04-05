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
import 'package:mobile_app/widgets/device_list_tabs/device_list_item.dart';
import 'package:mobile_app/widgets/device_list_tabs/group_list_item.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../theme.dart';

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
                    padding: MyTheme.inset,
                    itemCount: state.deviceGroups.length,
                    itemBuilder: (context, i) {
                      return Column(children: [
                        const Divider(),
                        GroupListItem(i, null),
                      ]);
                    },
                  )))
              : state.devices.isEmpty
                  ? state.loadingDevices
                      ? Center(
                          child: PlatformCircularProgressIndicator(),
                        )
                      : const Center(child: Text("No Devices"))
                  : ListView.builder(
                      padding: MyTheme.inset,
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
