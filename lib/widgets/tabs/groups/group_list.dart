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
import 'package:mobile_app/services/device_groups.dart';
import 'package:mobile_app/services/haptic_feedback_proxy.dart';
import 'package:mobile_app/widgets/tabs/device_tabs.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/detail_page.dart';
import 'package:provider/provider.dart';

import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/tabs/shared/group_list_item.dart';

class GroupList extends StatefulWidget {
  const GroupList({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _GroupListState();
}

class _GroupListState extends State<GroupList> with ResumeRefreshMixin {
  StreamSubscription? _fabSubscription;
  StreamSubscription? _refreshSubscription;
  DeviceTabsState? parentState;

  @override
  void dispose() {
    _fabSubscription?.cancel();
    _refreshSubscription?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    parentState = context.findAncestorStateOfType<State<DeviceTabs>>() as DeviceTabsState?;
    _fabSubscription = parentState?.fabPressed.listen((_) async {
      final titleController = TextEditingController(text: "");
      String? newName;
      if (!mounted) return;
      await showAdaptiveDialog(
          context: context,
          builder: (_) => AlertDialog.adaptive(
                title: const Text("New Group"),
                content: TextFormField(controller: titleController, decoration: InputDecoration(hintText: "Name")),
                actions: [
                  TextButton(
                    child: Text('Cancel'),
                    onPressed: () => Navigator.pop(context),
                  ),
                  TextButton(
                      child: Text('Create'),
                      onPressed: () {
                        newName = titleController.value.text;
                        Navigator.popUntil(context, (route) => route.isFirst);
                      })
                ],
              ));
      if (newName == null) {
        return;
      }

      AppState().deviceGroups.add(await DeviceGroupsService.createDeviceGroup(newName!));
      _openGroupPage(AppState().deviceGroups.length - 1, parentState);
      AppState().notifyListeners();
    });
    _refreshSubscription = AppState().refreshPressed.listen((_) {
      AppState().loadDeviceGroups();
    });
  }

  @override
  void onResumed() => AppState().loadDeviceGroups();

  void _openGroupPage(int i, DeviceTabsState? parentState) async {
    parentState?.filter.deviceGroupIds = [AppState().deviceGroups[i].id];
    AppState().searchDevices(parentState?.filter ?? DeviceSearchFilter("", null, null, [AppState().deviceGroups[i].id], null));
    await Navigator.push(context, MaterialPageRoute(builder: (context) => DetailPage(null, AppState().deviceGroups[i])));
    if (!mounted) return;
    // deviceGroupIds, not locationIds: this method sets the group filter, and
    // clearing the wrong one left the group filter applied after going back.
    parentState?.filter.deviceGroupIds = null;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, child) {
      return state.loadingDeviceGroups()
          ? const Center(child: DelayedCircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                HapticFeedbackProxy.lightImpact();
                state.loadDeviceGroups();
              },
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
                      itemCount: state.deviceGroups.length + 1,
                      itemBuilder: (context, i) {
                        return i < state.deviceGroups.length
                            ? Column(children: [
                          i > 0 ? const Divider() : const SizedBox.shrink(),
                                GroupListItem(state.deviceGroups[i], null),
                              ])
                            : Column(children: const [
                                Divider(),
                                ListTile(),
                              ]);
                      },
                    )));
    });
  }
}
