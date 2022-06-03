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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/services/locations.dart';
import 'package:mobile_app/widgets/tabs/locations/location_edit_groups.dart';
import 'package:provider/provider.dart';

import '../../../app_state.dart';
import '../../../models/location.dart';
import '../../../theme.dart';
import '../../shared/app_bar.dart';
import '../../shared/expandable_fab.dart';
import '../device_tabs.dart';
import '../shared/device_list_item.dart';
import '../shared/group_list_item.dart';
import 'location_edit_devices.dart';

class LocationPage extends StatefulWidget {
  final int _stateLocationIndex;
  final DeviceTabsState parentState;


  const LocationPage(this._stateLocationIndex, this.parentState, {Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => LocationPageState();
}

class LocationPageState extends State<LocationPage> with WidgetsBindingObserver {
  final StreamController _toggleStreamController = StreamController();
  late final Stream _toggleStream;

  LocationPageState() {
    _toggleStream = _toggleStreamController.stream.asBroadcastStream();
  }

  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  _refresh(Location location, BuildContext context) async {
    widget.parentState.filter.locationIds = [location.id];
    await AppState().loadDeviceGroups(context);
    await AppState().searchDevices(widget.parentState.filter, context, true);
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
    if (state == AppLifecycleState.resumed && ModalRoute.of(context)?.isCurrent == true) _refresh(AppState().locations[widget._stateLocationIndex], context);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, child) {
      if (state.locations.length - 1 < widget._stateLocationIndex) {
        _logger.w("Location Page requested for location index that is not in AppState");
        return Center(child: PlatformCircularProgressIndicator());
      }

      if ((state.loadingDevices || state.devices.length != state.locations[widget._stateLocationIndex].device_ids.length) && !state.allDevicesLoaded) {
        if (!state.loadingDevices) {
          state.loadDevices(context); //ensure all devices get loaded
        }
      }

      final location = state.locations[widget._stateLocationIndex];

      List<Widget> appBarActions = [];
      appBarActions.add(PlatformIconButton(
        onPressed: () async {
          final titleController = TextEditingController(text: location.name);

          final newName = await showPlatformDialog(
              context: context,
              builder: (context) => PlatformAlertDialog(
                    title: Text("Edit " + location.name),
                    content: PlatformTextFormField(controller: titleController),
                    actions: [
                      PlatformDialogAction(
                        child: PlatformText('Cancel'),
                        onPressed: () => Navigator.pop(context),
                      ),
                      PlatformDialogAction(
                          child: PlatformText('Save'),
                          onPressed: () {
                            Navigator.pop(context, titleController.value.text);
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
        icon: Icon(PlatformIcons(context).edit),
        cupertino: (_, __) => CupertinoIconButtonData(padding: EdgeInsets.zero),
      ));
      appBarActions.add(PlatformIconButton(
        onPressed: () async {
          final deleted = await showPlatformDialog(
              context: context,
              builder: (context) => PlatformAlertDialog(
                    title: Text("Do you want to permanently delete location '" + location.name + "'?"),
                    actions: [
                      PlatformDialogAction(
                        child: PlatformText('Cancel'),
                        onPressed: () => Navigator.pop(context),
                      ),
                      PlatformDialogAction(
                          child: PlatformText('Delete'),
                          cupertino: (_, __) => CupertinoDialogActionData(isDestructiveAction: true),
                          onPressed: () async {
                            await LocationService.deleteLocation(location.id);
                            state.locations.removeAt(widget._stateLocationIndex);
                            Navigator.pop(context, true);
                          })
                    ],
                  ));
          if (deleted == true) {
            Navigator.pop(context);
            state.notifyListeners();
          }
        },
        icon: Icon(PlatformIcons(context).delete),
        cupertino: (_, __) => CupertinoIconButtonData(padding: EdgeInsets.zero),
      ));
      if (kIsWeb) {
        appBarActions.add(PlatformIconButton(
          onPressed: () => _refresh(location, context),
          icon: const Icon(Icons.refresh),
          cupertino: (_, __) => CupertinoIconButtonData(padding: EdgeInsets.zero),
        ));
      }
      appBarActions.addAll(MyAppBar.getDefaultActions(context));

      final List<int> matchingGroups = [];
      for (var i = 0; i < state.deviceGroups.length; i++) {
        if (location.device_group_ids.contains(state.deviceGroups[i].id) &&
            (widget.parentState.filter.deviceGroupIds == null || widget.parentState.filter.deviceGroupIds!.contains(state.deviceGroups[i].id))) {
          matchingGroups.add(i);
        }
      }

      return Scaffold(
          floatingActionButton: ExpandableFab(
            icon: Icon(Icons.list, color: MyTheme.textColor),
            distance: 55.0,
            toggleStream: _toggleStream,
            children: [
              ActionButton(
                onPressed: () async {
                  _toggleStreamController.add(null);
                  await Navigator.push(context, platformPageRoute(context: context, builder: (context) => LocationEditDevices(widget._stateLocationIndex)));
                  state.searchDevices(widget.parentState.filter, context);
                },
                icon: Icon(Icons.sensors, color: MyTheme.textColor),
              ),
              ActionButton(
                onPressed: () {
                  _toggleStreamController.add(null);
                  Navigator.push(context, platformPageRoute(context: context, builder: (context) => LocationEditGroups(widget._stateLocationIndex)));
                },
                icon: Icon(Icons.devices_other, color: MyTheme.textColor),
              )
            ],
          ),
          body: PlatformScaffold(
            appBar: MyAppBar(location.name).getAppBar(context, appBarActions),
            body: state.loadingDevices || state.loadingDeviceGroups()
                ? Center(
                    child: PlatformCircularProgressIndicator(),
                  )
                : RefreshIndicator(
                    onRefresh: () async => await _refresh(location, context),
                    child: location.device_ids.isEmpty && location.device_group_ids.isEmpty
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
                                          child: Center(child: Text("Empty Location")),
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
                            itemCount: location.device_ids.length + matchingGroups.length + 1,
                            itemBuilder: (_, i) {
                              if (i > state.devices.length + matchingGroups.length - 1) {
                                state.loadDevices(context);
                                return Column(
                                  children: const [Divider(), ListTile()],
                                );
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
                                    widget.parentState.filter.locationIds = [location.id];
                                    state.searchDevices(
                                        widget.parentState.filter, context);
                                  })
                                ],
                              );
                            },
                          )),
          ));
    });
  }
}
