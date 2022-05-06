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
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../theme.dart';
import '../device_list.dart';
import 'group_list_item.dart';

class DeviceListFavorites extends StatelessWidget {
  const DeviceListFavorites({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, child) {
      if (state.devices.isEmpty) {
        state.loadDevices(context);
      }
      final List<int> matchingGroups = [];
      for (var i = 0; i < state.deviceGroups.length; i++) {
        if (state.deviceGroups[i].favorite) {
          matchingGroups.add(i);
        }
      }
      state.devices.removeWhere((element) => !element.favorite);
      return RefreshIndicator(
          onRefresh: () => state.refreshDevices(context),
          child: Scrollbar(
            child: state.devices.isEmpty && matchingGroups.isEmpty
                ? Center(
                    child: state.loadingDevices
                        ? PlatformCircularProgressIndicator()
                        : LayoutBuilder(
                            builder: (context, constraint) {
                              return SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(minHeight: constraint.maxHeight),
                                  child: IntrinsicHeight(
                                    child: Column(
                                      children: [
                                        Expanded(
                                            child: Center(
                                                child: PlatformElevatedButton(
                                          child: const Text("Add Favorites"),
                                          onPressed: () {
                                            final parentState = context.findAncestorStateOfType<State<DeviceList>>() as DeviceListState?;
                                            parentState?.switchBottomBar(5, true);
                                          },
                                        ))),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ))
                : ListView.builder(
                    padding: MyTheme.inset,
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
                          GroupListItem(matchingGroups.elementAt(i - state.devices.length), (_) {
                            final parentState = context.findAncestorStateOfType<State<DeviceList>>() as DeviceListState?;
                            if (parentState == null) return;
                            parentState.filter.deviceGroupIds = null;
                            state.searchDevices(parentState.filter, context);
                          })
                        ],
                      );
                    },
                  ),
          ));
    });
  }
}
