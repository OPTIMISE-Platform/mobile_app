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
import 'package:logger/logger.dart';
import 'package:mobile_app/services/locations.dart';
import 'package:provider/provider.dart';

import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/app_bar.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/shared/grouped_list_tile.dart';
import 'package:mobile_app/widgets/shared/slice_position.dart';

class LocationEditGroups extends StatefulWidget {
  final int _stateLocationIndex;
  final _logger = Logger(
    printer: SimplePrinter(),
  );

  LocationEditGroups(this._stateLocationIndex, {super.key});

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
        return const Center(child: DelayedCircularProgressIndicator());
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
              if (!context.mounted) return;
              Navigator.pop(context);
            },
            backgroundColor: context.appColors.app,
            label: const Text("Save"),
            icon: const Icon(Icons.save),
          ),
          body: Scaffold(
              appBar: MyAppBar(location.name).getAppBar(context, MyAppBar.getDefaultActions(context)),
              body: state.loadingDeviceGroups()
                  ? const Center(
                child: DelayedCircularProgressIndicator(),
              )
                  : ListView.builder(
                padding: Spacing.insetVertical,
                itemCount: state.deviceGroups.length,
                itemBuilder: (_, i) {
                  final group = state.deviceGroups[i];
                  return GroupedListTile(
                    key: ValueKey(group.id),
                    position: SlicePosition.forIndex(i, state.deviceGroups.length),
                    hairlineInset: GroupedListTile.insetIconLeading,
                    child: ListTile(
                      leading: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(
                          _selected.contains(group.id) ? Icons.check_circle : Icons.circle_outlined,
                          color: context.appColors.appInk,
                        )
                      ]),
                      title: Text(group.name),
                      onTap: () => setState(() => _selected.contains(group.id)
                          ? _selected.remove(group.id)
                          : _selected.add(group.id)),
                    ),
                  );
                },
                findChildIndexCallback: (key) {
                  final id = (key as ValueKey<String>).value;
                  final index = state.deviceGroups.indexWhere((g) => g.id == id);
                  return index == -1 ? null : index;
                },
              )),
        );
    });
  }
}
