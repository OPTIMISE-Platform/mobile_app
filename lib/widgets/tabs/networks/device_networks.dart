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

import 'package:badges/badges.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:provider/provider.dart';

import '../../../app_state.dart';
import '../../../models/device_instance.dart';
import '../../../models/device_search_filter.dart';
import '../../../theme.dart';
import '../device_tabs.dart';
import '../shared/device_list_item.dart';

class DeviceListByNetwork extends StatefulWidget {
  const DeviceListByNetwork({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _DeviceListByNetworkState();
}

class _DeviceListByNetworkState extends State<DeviceListByNetwork> with WidgetsBindingObserver {
  int? _selected;
  bool _loading = false;

  _refresh() async {
    if (_selected == null) {
      AppState().loadNetworks(context);
    } else {
      AppState().searchDevices(
          (context.findAncestorStateOfType<State<DeviceTabs>>() as DeviceTabsState?)?.filter ??
              DeviceSearchFilter("", null, null, [AppState().networks[_selected!].id]),
          context,
          true);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && ModalRoute.of(context)?.isCurrent == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, child) {
      final parentState = context.findAncestorStateOfType<State<DeviceTabs>>() as DeviceTabsState?;
      return Scrollbar(
          child: state.loadingNetworks()
              ? Center(child: PlatformCircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: () async => await _refresh(),
                  child: _selected == null
                      ? state.networks.isEmpty
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
                                            child: Center(child: Text("No Networks")),
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
                              itemCount: state.networks.length,
                              itemBuilder: (context, i) {
                                return Column(children: [
                                  const Divider(),
                                  ListTile(
                                      title: Container(
                                          alignment: Alignment.centerLeft,
                                          child: Badge(
                                            alignment: Alignment.centerLeft,
                                            padding: const EdgeInsets.only(left: MyTheme.insetSize),
                                            position: BadgePosition.topEnd(),
                                            badgeContent: Icon(PlatformIcons(context).error, size: 16, color: MyTheme.warnColor),
                                            showBadge: state.networks[i].getConnectionStatus() == DeviceConnectionStatus.offline,
                                            badgeColor: Colors.transparent,
                                            elevation: 0,
                                            child: Text(state.networks[i].name),
                                          )),
                                      subtitle: Text(
                                          "${(state.networks[i].device_local_ids ?? []).length} Device${(state.networks[i].device_local_ids ?? []).isEmpty || (state.networks[i].device_local_ids ?? []).length > 1 ? "s" : ""}"),
                                      onTap: (state.networks[i].device_local_ids ?? []).isEmpty
                                          ? null
                                          : () {
                                              _loading = true;
                                              parentState?.filter.addNetwork(state.networks[i].id);
                                              state
                                                  .searchDevices(parentState?.filter ?? DeviceSearchFilter("", null, null, [state.networks[i].id]),
                                                      context, true)
                                                  .then((_) => setState(() => _loading = true));
                                              parentState?.setState(() {
                                                parentState.hideSearch = false;
                                                parentState.onBackCallback = () {
                                                  parentState.setState(() {
                                                    parentState.filter.networkIds = null;
                                                    parentState.customAppBarTitle = null;
                                                    parentState.onBackCallback = null;
                                                    parentState.hideSearch = true;
                                                  });
                                                  setState(() => _selected = null);
                                                };
                                                parentState.customAppBarTitle = state.networks[i].name;

                                                setState(() {
                                                  _selected = i;
                                                });
                                              });
                                            },
                                      trailing: state.networks[i].localService == null
                                          ? null
                                          : (const Tooltip(
                                              message: "In local network",
                                              triggerMode: TooltipTriggerMode.tap,
                                              child: Icon(Icons.lan_outlined))))
                                ]);
                              },
                            )
                      : state.devices.isEmpty
                          ? state.loadingDevices || _loading
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
                            )));
    });
  }
}
