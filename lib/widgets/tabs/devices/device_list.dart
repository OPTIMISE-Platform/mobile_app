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
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/shared/sectioned_list_view.dart';
import 'package:mobile_app/widgets/tabs/shared/device_list_item.dart';

class DeviceList extends StatefulWidget {
  const DeviceList({super.key});

  @override
  State<StatefulWidget> createState() => _DeviceListState();
}

class _DeviceListState extends State<DeviceList> with ResumeRefreshMixin {
  StreamSubscription? _refreshSubscription;

  @override
  void dispose() {
    _refreshSubscription?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _refreshSubscription = AppState().refreshPressed.listen((_) {
      AppState().refreshDevices();
    });
  }

  @override
  void onResumed() => AppState().refreshDevices();

  @override
  Widget build(BuildContext context) {
    // Only rebuild the list *scaffolding* (spinner ↔ empty ↔ list, item count)
    // when those structural inputs change. Individual device *state* updates
    // (value, transitioning, connection) don't change this signature — each
    // DeviceListItem has its own Consumer<AppState> and refreshes itself, so we
    // avoid rebuilding the whole ListView/RefreshIndicator on every notify.
    return Selector<AppState, String>(
        selector: (_, state) =>
            '${state.loadingDevices}|${state.devices.length}|${state.rawDevicesFetched}|${state.devicesListEnded}',
        builder: (_, __, ___) => RefreshIndicator(
              onRefresh: () async {
                HapticFeedbackProxy.lightImpact();
                AppState().refreshDevices();
              },
              child: Scrollbar(
                child: AppState().loadingDevices
                    ? const Center(child: DelayedCircularProgressIndicator())
                    // devicesListEnded, not just an empty list: an all-hidden
                    // page must still fall through to the ListView below, or
                    // its own row never fetches the next page.
                    : AppState().devices.isEmpty && AppState().devicesListEnded
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
                                          child: Center(child: Text("No Devices")),
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
                              ListSection<DeviceInstance>(
                                id: "devices",
                                items: AppState().devices,
                                keyOf: (device) => device.id,
                                itemBuilder: (_, device, position) =>
                                    DeviceListItem(device, null,
                                        position: position),
                              ),
                            ],
                            trailing: [
                              if (AppState().devicesListItemCount >
                                  AppState().devices.length)
                                Builder(builder: (_) {
                                  AppState().loadDevices();
                                  return const SizedBox.shrink();
                                }),
                            ]),
              ),
            ));
  }
}
