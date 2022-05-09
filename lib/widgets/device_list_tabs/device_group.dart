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

import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:mobile_app/services/device_groups.dart';
import 'package:mobile_app/widgets/device_list.dart';
import 'package:mobile_app/widgets/device_list_tabs/device_list_item.dart';
import 'package:mobile_app/widgets/device_list_tabs/group_list_item.dart';
import 'package:mobile_app/widgets/device_page.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../models/device_search_filter.dart';
import '../../theme.dart';

class DeviceGroupList extends StatefulWidget {
  const DeviceGroupList({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _DeviceGroupListState();
}

class _DeviceGroupListState extends State<DeviceGroupList> {
  int? _selected;

  static StreamSubscription? _fabSubscription;

  @override
  void dispose() {
    _fabSubscription?.cancel().then((_) => _fabSubscription = null);
    super.dispose();
  }

  void _openGroupPage(int i, DeviceListState? parentState) async {
    parentState?.filter.deviceGroupIds = [AppState().deviceGroups[i].id];
    AppState().searchDevices(parentState?.filter ?? DeviceSearchFilter("", null, null, [AppState().deviceGroups[i].id], null), context);
    await Navigator.push(context, platformPageRoute(context: context, builder: (context) => DevicePage(null, i)));
    parentState?.filter.locationIds = null;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, child) {
      final parentState = context.findAncestorStateOfType<State<DeviceList>>() as DeviceListState?;
      _fabSubscription ??= parentState?.fabPressed.listen((_) async {
        final titleController = TextEditingController(text: "");
        String? newName;
        await showPlatformDialog(
            context: context,
            builder: (_) => PlatformAlertDialog(
              title: const Text("New Group"),
              content: PlatformTextFormField(controller: titleController, hintText: "Name"),
              actions: [
                PlatformDialogAction(
                  child: PlatformText('Cancel'),
                  onPressed: () => Navigator.pop(context),
                ),
                PlatformDialogAction(
                    child: PlatformText('Create'),
                    onPressed: () {
                      newName = titleController.value.text;
                      Navigator.popUntil(context, (route) => route.isFirst);
                    })
              ],
            ));
        if (newName == null) {
          return;
        }

        state.deviceGroups.add(await DeviceGroupsService.createDeviceGroup(newName!));
        _openGroupPage(state.deviceGroups.length - 1, parentState);
        state.notifyListeners();
      });
      return state.loadingDeviceGroups()
          ? Center(child: PlatformCircularProgressIndicator())
          : _selected == null
              ? RefreshIndicator(
                  onRefresh: () => state.loadDeviceGroups(context),
                  child: state.deviceGroups.isEmpty
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
                                        child: Center(child: Text("No Groups")),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        )
                      : Scrollbar(
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
