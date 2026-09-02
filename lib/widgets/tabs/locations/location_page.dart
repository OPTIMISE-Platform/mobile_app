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
import 'package:logger/logger.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/services/locations.dart';
import 'package:mobile_app/widgets/tabs/locations/location_edit_groups.dart';
import 'package:provider/provider.dart';

import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/location.dart';
import 'package:mobile_app/services/haptic_feedback_proxy.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/app_bar.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/shared/expandable_fab.dart';
import 'package:mobile_app/widgets/tabs/device_tabs.dart';
import 'package:mobile_app/widgets/tabs/shared/device_list_item.dart';
import 'package:mobile_app/widgets/tabs/shared/group_list_item.dart';
import 'package:mobile_app/widgets/tabs/locations/location_edit_devices.dart';

class LocationPage extends StatefulWidget {
  final int _stateLocationIndex;
  final DeviceTabsState parentState;

  const LocationPage(this._stateLocationIndex, this.parentState, {super.key});

  @override
  State<StatefulWidget> createState() => LocationPageState();
}

class LocationPageState extends State<LocationPage>
    with ResumeRefreshMixin {
  final StreamController _toggleStreamController = StreamController();
  late final Stream _toggleStream;

  LocationPageState() {
    _toggleStream = _toggleStreamController.stream.asBroadcastStream();
  }

  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  _refresh(Location location) async {
    widget.parentState.filter.locationIds = [location.id];
    await AppState().loadDeviceGroups();
    await AppState().searchDevices(widget.parentState.filter, true);
  }

  @override
  void onResumed() =>
      _refresh(AppState().locations[widget._stateLocationIndex]);

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, child) {
      if (state.locations.length - 1 < widget._stateLocationIndex) {
        _logger.w(
            "Location Page requested for location index that is not in AppState");
        return const Center(child: DelayedCircularProgressIndicator());
      }

      if ((state.loadingDevices ||
              state.devices.length !=
                  state.locations[widget._stateLocationIndex].device_ids
                      .length) &&
          !state.allDevicesLoaded) {
        if (!state.loadingDevices) {
          state.loadDevices(); //ensure all devices get loaded
        }
      }

      final location = state.locations[widget._stateLocationIndex];

      List<Widget> appBarActions = [];
      if (LocationService.isCreateEditDeleteAvailable()) {
        appBarActions.add(IconButton(
          onPressed: () async {
            final titleController = TextEditingController(text: location.name);

            final newName = await showAdaptiveDialog(
                context: context,
                builder: (context) =>
                    AlertDialog.adaptive(
                      title: Text("Edit ${location.name}"),
                      content:
                      TextFormField(controller: titleController),
                      actions: [
                        TextButton(
                          child: const Text('Cancel'),
                          onPressed: () => Navigator.pop(context),
                        ),
                        TextButton(
                            child: const Text('Save'),
                            onPressed: () {
                              Navigator.pop(
                                  context, titleController.value.text);
                            })
                      ],
                    ));
            if (newName == null) {
              return;
            }
            location.name = newName;
            final newLocation = await LocationService.saveLocation(location);
            state.locations[widget._stateLocationIndex] = newLocation;
            state.notifyListeners();
          },
          icon: const Icon(Icons.edit),
        ));

        appBarActions.add(IconButton(
          onPressed: () async {
            final deleted = await showAdaptiveDialog(
                context: context,
                builder: (context) =>
                    AlertDialog.adaptive(
                      title: Text(
                          "Do you want to permanently delete location '${location
                              .name}'?"),
                      actions: [
                        TextButton(
                          child: const Text('Cancel'),
                          onPressed: () => Navigator.pop(context),
                        ),
                        TextButton(
                            child: const Text('Delete'),
                            onPressed: () async {
                              await LocationService.deleteLocation(location.id);
                              state.locations
                                  .removeAt(widget._stateLocationIndex);
                              if (!context.mounted) return;
                              Navigator.pop(context, true);
                            })
                      ],
                    ));
            if (deleted == true) {
              if (context.mounted) Navigator.pop(context);
              state.notifyListeners();
            }
          },
          icon: const Icon(Icons.delete),
        ));
      }
      appBarActions.addAll(MyAppBar.getDefaultActions(context));

      final List<DeviceGroup> matchingGroups = [];
      for (var i = 0; i < state.deviceGroups.length; i++) {
        if (location.device_group_ids.contains(state.deviceGroups[i].id) &&
            (widget.parentState.filter.deviceGroupIds == null ||
                widget.parentState.filter.deviceGroupIds!
                    .contains(state.deviceGroups[i].id))) {
          matchingGroups.add(state.deviceGroups[i]);
        }
      }

      return Scaffold(
          floatingActionButton: !LocationService.isCreateEditDeleteAvailable() ? null : ExpandableFab(
            icon: Icon(Icons.list, color: MyTheme.textColor),
            distance: 55.0,
            toggleStream: _toggleStream,
            children: [
              ActionButton(
                onPressed: () async {
                  _toggleStreamController.add(null);
                  await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) =>
                              LocationEditDevices(widget._stateLocationIndex)));
                  state.searchDevices(widget.parentState.filter);
                },
                icon: Icon(Icons.sensors, color: MyTheme.textColor),
              ),
              ActionButton(
                onPressed: () {
                  _toggleStreamController.add(null);
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) =>
                              LocationEditGroups(widget._stateLocationIndex)));
                },
                icon: Icon(Icons.devices_other, color: MyTheme.textColor),
              )
            ],
          ),
          body: Scaffold(
            appBar: MyAppBar(location.name).getAppBar(context, appBarActions),
            body: state.loadingDevices || state.loadingDeviceGroups()
                ? const Center(
                    child: DelayedCircularProgressIndicator(),
                  )
                : RefreshIndicator(
                    onRefresh: () async {
                      HapticFeedbackProxy.lightImpact();
                      await _refresh(location);
                    },
                    child: location.device_ids.isEmpty &&
                            location.device_group_ids.isEmpty
                        ? LayoutBuilder(
                            builder: (context, constraint) {
                              return SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                      minHeight: constraint.maxHeight),
                                  child: const IntrinsicHeight(
                                    child: Column(
                                      children: [
                                        Expanded(
                                          child: Center(
                                              child: Text("Empty Location")),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          )
                        : ListView.builder(
                            padding: MyTheme.inset,
                            itemCount: location.device_ids.length +
                                matchingGroups.length +
                                1,
                            itemBuilder: (_, i) {
                              if (i >
                                  state.devices.length +
                                      matchingGroups.length -
                                      1) {
                                state.loadDevices();
                                return const Column(
                                  children: [Divider(), ListTile()],
                                );
                              }
                              if (i < state.devices.length) {
                                return Column(
                                  children: [
                                    i > 0
                                        ? const Divider()
                                        : const SizedBox.shrink(),
                                    DeviceListItem(state.devices[i], null)
                                  ],
                                );
                              }
                              return Column(
                                children: [
                                  i > 0
                                      ? const Divider()
                                      : const SizedBox.shrink(),
                                  GroupListItem(
                                      matchingGroups.elementAt(
                                          i - state.devices.length), (_) {
                                    widget.parentState.filter.locationIds = [
                                      location.id
                                    ];
                                    state.searchDevices(
                                        widget.parentState.filter);
                                  })
                                ],
                              );
                            },
                          )),
          ));
    });
  }
}
