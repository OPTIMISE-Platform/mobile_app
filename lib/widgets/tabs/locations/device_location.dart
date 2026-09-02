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
import 'package:mobile_app/services/locations.dart';
import 'package:mobile_app/widgets/tabs/locations/location_page.dart';
import 'package:provider/provider.dart';

import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/services/haptic_feedback_proxy.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/tabs/device_tabs.dart';

class DeviceListByLocation extends StatefulWidget {
  const DeviceListByLocation({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _DeviceListByLocationState();
}

class _DeviceListByLocationState extends State<DeviceListByLocation>
    with ResumeRefreshMixin {
  // Not static: a static field let a second instance overwrite the first
  // instance's subscription (leak) and the first's dispose cancel the
  // second's — the FAB silently died after leaving and re-entering the tab.
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
    AppState().loadLocations();
    parentState = context.findAncestorStateOfType<State<DeviceTabs>>()
        as DeviceTabsState?;
    _fabSubscription = parentState?.fabPressed.listen((_) async {
      final titleController = TextEditingController(text: "");
      String? newName;
      if (!mounted) return;
      await showAdaptiveDialog(
          context: context,
          builder: (_) => AlertDialog.adaptive(
                title: const Text("New Location"),
                content: TextFormField(
                    controller: titleController, decoration: InputDecoration(hintText: "Name")),
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

      AppState().locations.add(await LocationService.createLocation(newName!));
      _openLocationPage(AppState().locations.length - 1, parentState);
      AppState().notifyListeners();
    });
    _refreshSubscription = AppState().refreshPressed.listen((_) {
      AppState().loadLocations();
    });
  }

  @override
  void onResumed() {
    AppState().loadLocations();
    setState(() {});
  }

  void _openLocationPage(int i, DeviceTabsState? parentState) async {
    parentState?.filter.locationIds = [AppState().locations[i].id];
    AppState().searchDevices(
        parentState?.filter ??
            DeviceSearchFilter(
                "", null, null, null, [AppState().locations[i].id]));
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => LocationPage(i, parentState!)));
    parentState?.filter.locationIds = null;
  }

  @override
  Widget build(BuildContext _) {
    return Consumer<AppState>(builder: (_, state, child) {
      return Scrollbar(
          child: state.loadingLocations()
              ? const Center(child: DelayedCircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: () async {
                    HapticFeedbackProxy.lightImpact();
                    state.loadLocations();
                  },
                  child: state.locations.isEmpty
                      ? LayoutBuilder(
                          builder: (context, constraint) {
                            return SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                    minHeight: constraint.maxHeight),
                                child: IntrinsicHeight(
                                  child: Column(
                                    children: const [
                                      Expanded(
                                        child:
                                            Center(child: Text("No Locations")),
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
                          itemCount: state.locations.length + 1,
                          itemBuilder: (context, i) {
                            return i < state.locations.length
                                ? Column(children: [
                                    i > 0
                                        ? const Divider()
                                        : const SizedBox.shrink(),
                                    ListTile(
                                        title: Text(state.locations[i].name),
                                        leading: Container(
                                          height: MediaQuery.of(context)
                                                  .textScaleFactor *
                                              48,
                                          width: MediaQuery.of(context)
                                                  .textScaleFactor *
                                              48,
                                          decoration: BoxDecoration(
                                              color: const Color(0xFF6c6c6c),
                                              borderRadius:
                                                  BorderRadius.circular(50)),
                                          child: Padding(
                                            padding: EdgeInsets.all(
                                                MediaQuery.of(context)
                                                        .textScaleFactor *
                                                    8),
                                            child: state
                                                    .locations[i].imageWidget ??
                                                const Icon(Icons.location_on,
                                                    color: Colors.white),
                                          ),
                                        ),
                                        subtitle: Text(
                                            "${state.locations[i].device_ids.length} Device${state.locations[i].device_ids.length > 1 || state.locations[i].device_ids.isEmpty ? "s" : ""}, ${state.locations[i].device_group_ids.length} Group${state.locations[i].device_group_ids.length > 1 || state.locations[i].device_group_ids.isEmpty ? "s" : ""}"),
                                        onTap: () =>
                                            _openLocationPage(i, parentState))
                                  ])
                                : Column(
                                    children: const [Divider(), ListTile()],
                                  );
                          },
                        )));
    });
  }
}
