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
import '../../models/device_instance.dart';
import '../../models/device_search_filter.dart';
import '../../theme.dart';
import '../device_list.dart';

class DeviceListByNetwork extends StatefulWidget {
  const DeviceListByNetwork({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _DeviceListByNetworkState();
}

class _DeviceListByNetworkState extends State<DeviceListByNetwork> {
  int? _selected;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, child) {
      return Scrollbar(
        child: state.networks.isEmpty || state.loadingNetworks()
            ? Center(child: PlatformCircularProgressIndicator())
            : _selected == null
                ? ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: MyTheme.inset,
                    itemCount: state.networks.length,
                    itemBuilder: (context, i) {
                      return Column(children: [
                        const Divider(),
                        ListTile(
                            title: Text(state.networks[i].name),
                            leading: state.networks[i].getConnectionStatus() == DeviceConnectionStatus.offline
                                ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                    Tooltip(message: "Network is offline", child: Icon(PlatformIcons(context).error, color: MyTheme.warnColor))
                                  ])
                                : null,
                            subtitle: Text((state.networks[i].device_local_ids ?? []).length.toString() +
                                " Device" +
                                ((state.networks[i].device_local_ids ?? []).isEmpty || (state.networks[i].device_local_ids ?? []).length > 1
                                    ? "s"
                                    : "")),
                            onTap: (state.networks[i].device_local_ids ?? []).isEmpty
                                ? null
                                : () {
                                    _loading = true;
                                    state.searchDevices(DeviceSearchFilter("", null, null, state.networks[i].id), context, true).then((_) => setState(() => _loading = true));
                                    final parentState = context.findAncestorStateOfType<State<DeviceList>>() as DeviceListState?;
                                    parentState?.setState(() {
                                      parentState.onBackCallback = () {
                                        parentState.setState(() {
                                          parentState.customAppBarTitle = null;
                                          parentState.onBackCallback = null;
                                        });
                                        setState(() => _selected = null);
                                      };
                                      parentState.customAppBarTitle = state.networks[i].name;

                                      setState(() {
                                        _selected = i;
                                      });
                                    });
                                  })
                      ]);
                    },
                  )
                : state.devices.isEmpty
                    ? state.loadingDevices() || _loading
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
                      ),
      );
    });
  }
}
