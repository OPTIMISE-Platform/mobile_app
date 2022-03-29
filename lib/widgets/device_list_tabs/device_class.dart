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
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/device_search_filter.dart';
import '../../theme.dart';
import '../device_list.dart';

class DeviceListByDeviceClass extends StatefulWidget {
  const DeviceListByDeviceClass({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _DeviceListByDeviceClassState();
}

class _DeviceListByDeviceClassState extends State<DeviceListByDeviceClass> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, child) {
      final deviceClasses = state.deviceClasses.values.toList(growable: false);

      return Scrollbar(
        child: state.deviceClasses.isEmpty
            ? Center(child: PlatformCircularProgressIndicator())
            : _selected == null
                ? ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: MyTheme.inset,
                    itemCount: deviceClasses.length,
                    itemBuilder: (context, i) {
                      return Column(children: [
                        const Divider(),
                        ListTile(
                            title: Text(deviceClasses[i].name),
                            trailing: Container(
                              height: MediaQuery.of(context).textScaleFactor * 48,
                              width: MediaQuery.of(context).textScaleFactor * 48,
                              decoration: BoxDecoration(color: const Color(0xFF6c6c6c), borderRadius: BorderRadius.circular(50)),
                              child: Padding(
                                padding: EdgeInsets.all(MediaQuery.of(context).textScaleFactor * 8),
                                child: deviceClasses[i].imageWidget ?? const Icon(Icons.devices, color: Colors.white),
                              ),
                            ),
                            onTap: () {
                              final parentState = context.findAncestorStateOfType<State<DeviceList>>() as DeviceListState?;
                              parentState?.filter.deviceClassIds = [deviceClasses[i].id];
                              state.searchDevices(parentState?.filter ?? DeviceSearchFilter("", [deviceClasses[i].id]), context, true);
                              parentState?.setState(() {
                                parentState.onBackCallback = () {
                                  parentState.setState(() {
                                    parentState.customAppBarTitle = null;
                                    parentState.onBackCallback = null;
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
                  )
                : state.devices.isEmpty
                    ? state.loadingDevices()
                        ? Center(
                            child: PlatformCircularProgressIndicator(),
                          )
                        : const Center(child: Text("No Devices"))
                    : ListView.builder(
                        padding: MyTheme.inset,
                        itemCount: state.totalDevices,
                        itemBuilder: (_, i) {
                          if (i >= state.devices.length) {
                            state.loadDevices(context);
                            return const SizedBox.shrink();
                          }
                          return Column(
                            children: [const Divider(), DeviceListItem(i, null)],
                          );
                        },
                      ),
      );
    });
  }
}
