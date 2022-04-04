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

class DeviceListFavorites extends StatelessWidget {
  const DeviceListFavorites({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, child) {
      if (state.devices.isEmpty) {
        state.loadDevices(context);
      }
      return RefreshIndicator(
          onRefresh: () => state.refreshDevices(context),
          child: Scrollbar(
            child: state.devices.isEmpty
                ? Center(
                    child: state.loadingDevices()
                        ? PlatformCircularProgressIndicator()
                        : PlatformElevatedButton(
                            child: const Text("Add Favorites"),
                            onPressed: () {
                              final parentState = context.findAncestorStateOfType<State<DeviceList>>() as DeviceListState?;
                              parentState?.switchBottomBar(5, state, true);
                            },
                          ))
                : ListView.builder(
                    padding: MyTheme.inset,
                    itemCount: state.totalDevices,
                    itemBuilder: (_, i) {
                      if (i > state.devices.length - 1) {
                        state.loadDevices(context, i);
                        return const SizedBox.shrink();
                      }
                      return Column(
                        children: [const Divider(), DeviceListItem(i, null)],
                      );
                    },
                  ),
          ));
    });
  }
}
