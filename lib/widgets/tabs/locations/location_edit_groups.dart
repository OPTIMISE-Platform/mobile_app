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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/services/locations.dart';
import 'package:provider/provider.dart';

import '../../../app_state.dart';
import '../../../theme.dart';
import '../../shared/app_bar.dart';

class LocationEditGroups extends StatefulWidget {
  final int _stateLocationIndex;
  final _logger = Logger(
    printer: SimplePrinter(),
  );

  LocationEditGroups(this._stateLocationIndex, {Key? key}) : super(key: key) {}

  @override
  State<StatefulWidget> createState() => _LocationEditGroupsState();
}

class _LocationEditGroupsState extends State<LocationEditGroups> {
  final Set<String> _selected = {};
  bool _initialized = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, child) {
      if (state.locations.length - 1 < widget._stateLocationIndex) {
        widget._logger.w("LocationEditGroups requested for location index that is not in AppState");
        return Center(child: PlatformCircularProgressIndicator());
      }

      final location = state.locations[widget._stateLocationIndex];
      if (!_initialized) {
        _selected.addAll(location.device_group_ids);
        _initialized = true;
      }

        return Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () async {
              state.locations[widget._stateLocationIndex].device_group_ids = _selected.toList();
              await LocationService.saveLocation(state.locations[widget._stateLocationIndex]);
              state.notifyListeners();
              Navigator.pop(context);
            },
            backgroundColor: MyTheme.appColor,
            label: Text("Save", style: TextStyle(color: MyTheme.textColor)),
            icon: Icon(Icons.save, color: MyTheme.textColor),
          ),
          body: PlatformScaffold(
              appBar: MyAppBar(location.name).getAppBar(context, MyAppBar.getDefaultActions(context)),
              body: state.loadingDeviceGroups()
                  ? Center(
                child: PlatformCircularProgressIndicator(),
              )
                  : ListView.builder(
                padding: MyTheme.inset,
                itemCount: state.deviceGroups.length,
                itemBuilder: (_, i) {
                  return Column(
                    children: [
                      const Divider(),
                      ListTile(
                        leading: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(
                            _selected.contains(state.deviceGroups[i].id) ? PlatformIcons(context).checkMarkCircledSolid : Icons.circle_outlined,
                            color: MyTheme.appColor,
                          )
                        ]),
                        title: Text(state.deviceGroups[i].name),
                        onTap: () => setState(() => _selected.contains(state.deviceGroups[i].id)
                            ? _selected.remove(state.deviceGroups[i].id)
                            : _selected.add(state.deviceGroups[i].id)),
                      )
                    ],
                  );
                },
              )),
        );
    });
  }
}
