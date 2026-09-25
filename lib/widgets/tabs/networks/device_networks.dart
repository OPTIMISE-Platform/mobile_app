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
import 'package:mobile_app/widgets/tabs/gateways/mgw_page.dart';
import 'package:mobile_app/widgets/tabs/gateways/mgw_status_dot.dart';
import 'package:provider/provider.dart';

import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/shared/grouped_list_tile.dart';
import 'package:mobile_app/widgets/shared/slice_position.dart';
import 'package:mobile_app/widgets/tabs/device_tabs.dart';
import 'package:mobile_app/widgets/tabs/shared/device_list_item.dart';

import '../../../services/mgw/storage.dart';

class DeviceListByNetwork extends StatefulWidget {
  const DeviceListByNetwork({super.key});

  @override
  State<StatefulWidget> createState() => _DeviceListByNetworkState();
}

class _DeviceListByNetworkState extends State<DeviceListByNetwork>
    with ResumeRefreshMixin {
  int? _selected;
  bool _loading = false;
  StreamSubscription? _refreshSubscription;

  _refresh() async {
    if (!mounted) return;
    if (_selected == null) {
      AppState().loadNetworks(context);
    } else {
      AppState().searchDevices(
          (context.findAncestorStateOfType<State<DeviceTabs>>()
                      as DeviceTabsState?)
                  ?.filter ??
              DeviceSearchFilter(
                  "", null, null, [AppState().networks[_selected!].id]), true);
    }
  }

  @override
  void initState() {
    super.initState();
    _refreshSubscription = AppState().refreshPressed.listen((_) {
      _refresh();
    });
  }

  @override
  void dispose() {
    _refreshSubscription?.cancel();
    super.dispose();
  }

  /// Trailing control of a network row.
  ///
  /// Without a bound gateway it offers to add one. With one it shows what that
  /// gateway is currently good for - paired alone says nothing, since the
  /// device may be elsewhere or the gateway may have forgotten it - and opens
  /// the unpair dialog on tap.
  Widget _gatewayControl(AppState state, Network network) {
    final bound = state.gateways.where((mgw) => mgw.networkId == network.id);
    if (bound.isEmpty) {
      return IconButton(
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddLocalNetwork()),
          );
          _refresh();
        },
        icon: const Icon(Icons.add),
      );
    }
    final mgw = bound.first;
    return IconButton(
      onPressed: () => _showUnpairDialog(mgw),
      icon: Row(mainAxisSize: MainAxisSize.min, children: [
        MgwStatusDot(
            host: mgw.ip, expectNetworkId: mgw.networkId, size: 12),
        const SizedBox(width: 4),
        const Icon(Icons.lan_outlined),
      ]),
    );
  }

  void _showUnpairDialog(MGW mgw) {
    showDialog(
      context: context,
      builder: (BuildContext context) => SimpleDialog(
        title: const Text('Remove Pairing'),
        children: <Widget>[
          Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
            child: Text("${mgw.mDNSServiceName} - ${mgw.ip}"),
          ),
          Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 16.0, horizontal: 16.0),
            child: ElevatedButton(
              onPressed: () async {
                // Awaited: it clears the stored secrets. loadStoredMGWs then
                // has to run too - the row reads AppState.gateways, which only
                // that call refills, so without it the removed pairing stays
                // on screen.
                await MgwStorage.RemovePairedMGW(mgw);
                await AppState().loadStoredMGWs();
                if (!context.mounted) return;
                Navigator.pop(context, 'OK');
                _refresh();
              },
              child: const Text('OK'),
            ),
          )
        ],
      ),
    );
  }

  @override
  void onResumed() => _refresh();

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, child) {
      final parentState = context.findAncestorStateOfType<State<DeviceTabs>>()
          as DeviceTabsState?;
      return Scrollbar(
          child: state.loadingNetworks()
              ? const Center(child: DelayedCircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: () async {
                    HapticFeedbackProxy.lightImpact();
                    await _refresh();
                  },
                  child: _selected == null
                      ? state.networks.isEmpty
                          ? LayoutBuilder(
                              builder: (context, constraint) {
                                return SingleChildScrollView(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                        minHeight: constraint.maxHeight),
                                    child: const IntrinsicHeight(
                                      child: Column(
                                        children: [
                                          Expanded(
                                            child: Center(
                                                child: Text("No Networks")),
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
                              padding: Spacing.insetVertical,
                              itemCount: state.networks.length,
                              itemBuilder: (context, i) {
                                return GroupedListTile(
                                  key: ValueKey(state.networks[i].id),
                                  position: SlicePosition.forIndex(
                                      i, state.networks.length),
                                  hairlineInset: GroupedListTile.insetNoLeading,
                                  child: ListTile(
                                      title: Row(children: [
                                        // Flexible with an ellipsis: a network
                                        // name is free text and overflows the
                                        // row as soon as it is long.
                                        Flexible(
                                          child: Text(
                                            state.networks[i].name,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Badge(
                                          // backgroundColor below is
                                          // transparent, so this icon sits
                                          // directly on the page surface.
                                          label: Icon(
                                              Icons.error,
                                              size: 16,
                                              color: context.appColors.warnInk),
                                          isLabelVisible: state.networks[i]
                                                  .connection_state ==
                                              DeviceConnectionStatus.offline,
                                          alignment:
                                              AlignmentDirectional.topCenter,
                                          largeSize: 16,
                                          backgroundColor: Colors.transparent,
                                          child: state.networks[i]
                                                      .connection_state ==
                                                  DeviceConnectionStatus.offline
                                              ? const Text("")
                                              : null,
                                        )
                                      ]),
                                      subtitle: Text(
                                          "${(state.networks[i].device_local_ids ?? []).length} Device${(state.networks[i].device_local_ids ?? []).isEmpty || (state.networks[i].device_local_ids ?? []).length > 1 ? "s" : ""}"),
                                      onTap: (state.networks[i]
                                                      .device_local_ids ??
                                                  [])
                                              .isEmpty
                                          ? null
                                          : () {
                                              _loading = true;
                                              parentState?.filter.addNetwork(
                                                  state.networks[i].id);
                                              state
                                                  .searchDevices(
                                                      parentState?.filter ??
                                                          DeviceSearchFilter(
                                                              "", null, null, [
                                                            state.networks[i].id
                                                          ]), true)
                                                  .then((_) {
                                                // Guarded: the search is a
                                                // network call, and leaving the
                                                // tab before it answers used to
                                                // land here on a disposed
                                                // state.
                                                if (!mounted) return;
                                                setState(() => _loading = false);
                                              });
                                              parentState?.setState(() {
                                                parentState
                                                    .setHideSearchOverride(
                                                    false);
                                                parentState.onBackCallback =
                                                    () {
                                                  parentState.setState(() {
                                                    parentState.filter
                                                        .networkIds = null;
                                                    parentState
                                                            .customAppBarTitle =
                                                        null;
                                                    parentState.onBackCallback =
                                                        null;
                                                    parentState
                                                        .setHideSearchOverride(
                                                        null);
                                                  });
                                                  // The callback lives on the
                                                  // parent state and therefore
                                                  // outlives this widget.
                                                  if (mounted) {
                                                    setState(
                                                        () => _selected = null);
                                                  }
                                                };
                                                parentState.customAppBarTitle =
                                                    state.networks[i].name;

                                                setState(() {
                                                  _selected = i;
                                                });
                                              });
                                            },
                                      trailing: _gatewayControl(
                                          state, state.networks[i])),
                                );
                              },
                              findChildIndexCallback: (key) {
                                final id = (key as ValueKey<String>).value;
                                final index = state.networks
                                    .indexWhere((n) => n.id == id);
                                return index == -1 ? null : index;
                              },
                            )
                      : state.devices.isEmpty
                          ? state.loadingDevices || _loading
                              ? const Center(
                                  child: DelayedCircularProgressIndicator(),
                                )
                              : const Center(child: Text("No Devices"))
                          : ListView.builder(
                              padding: Spacing.insetVertical,
                              itemCount: state.totalDevices,
                              itemBuilder: (_, i) {
                                if (i > state.devices.length - 1) {
                                  return const SizedBox.shrink();
                                }
                                final device = state.devices[i];
                                return DeviceListItem(device, null,
                                    key: ValueKey(device.id),
                                    position: SlicePosition.forIndex(
                                        i, state.devices.length));
                              },
                              findChildIndexCallback: (key) {
                                final id = (key as ValueKey<String>).value;
                                final index = state.devices
                                    .indexWhere((d) => d.id == id);
                                return index == -1 ? null : index;
                              },
                            )));
    });
  }
}
