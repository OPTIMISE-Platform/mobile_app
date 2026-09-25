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
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/shared/slice_position.dart';
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
            '${state.loadingDevices}|${state.devices.length}|${state.totalDevices}',
        builder: (_, __, ___) => RefreshIndicator(
              onRefresh: () async {
                HapticFeedbackProxy.lightImpact();
                AppState().refreshDevices();
              },
              child: Scrollbar(
                child: AppState().loadingDevices
                    ? const Center(child: DelayedCircularProgressIndicator())
                    : AppState().devices.isEmpty
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
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: Spacing.listPadding(context),
                            itemCount: AppState().totalDevices,
                            itemBuilder: (context, i) {
                              if (i >= AppState().devices.length) {
                                AppState().loadDevices();
                              }
                              if (i > AppState().devices.length - 1) {
                                return const SizedBox.shrink();
                              }
                              final device = AppState().devices[i];
                              return DeviceListItem(device, null,
                                  key: ValueKey(device.id),
                                  position: SlicePosition.forIndex(
                                      i, AppState().devices.length));
                            },
                            // Keeps a row's expanded/transitioning State tied
                            // to its device when devices are inserted/removed
                            // ahead of it, not to its position in the list.
                            findChildIndexCallback: (key) {
                              final id = (key as ValueKey<String>).value;
                              final index = AppState()
                                  .devices
                                  .indexWhere((d) => d.id == id);
                              return index == -1 ? null : index;
                            }),
              ),
            ));
  }
}
