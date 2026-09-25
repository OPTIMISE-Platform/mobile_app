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
import 'package:logger/logger.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/services/devices.dart';
import 'package:mobile_app/services/locations.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:provider/provider.dart';

import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/app_bar.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/shared/grouped_list_tile.dart';
import 'package:mobile_app/widgets/shared/slice_position.dart';
import 'package:mobile_app/widgets/tabs/shared/search_delegate.dart';

class LocationEditDevices extends StatefulWidget {
  final int _stateLocationIndex;
  final _logger = Logger(
    printer: SimplePrinter(),
  );

  LocationEditDevices(this._stateLocationIndex, {super.key});

  @override
  State<StatefulWidget> createState() => _LocationEditDevicesState();
}

class _LocationEditDevicesState extends State<LocationEditDevices> {
  final Set<String> _selected = {};
  bool _initialized = false;
  Timer? _searchDebounce;
  bool _searchClosed = false;
  bool _delegateOpen = false;

  DeviceSearchFilter filter = DeviceSearchFilter("");
  List<DeviceInstance> _inactiveMembers = [];

  _searchChanged(String search) {
    if (filter.query == search) {
      return;
    }
    if (search.isNotEmpty && _searchClosed) {
      return; // catches delayed search requests, when search has been cancelled
    }
    filter.query = search;
    if (_searchDebounce?.isActive ?? false) _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      AppState().searchDevices(filter);
    });
  }

  /// Members the device search hides as inactive. The list shows them on top
  /// so they can still be deselected instead of staying in the location unseen.
  Future<void> _loadInactiveMembers(List<String> ids) async {
    if (ids.isEmpty) return;
    try {
      final members = await DevicesService.getDevicesByIds(ids);
      if (!mounted) return;
      setState(() {
        _inactiveMembers =
            members.where((d) => d.isInactive).toList(growable: false);
      });
      AppState().notifyListeners(); // redraws SearchDelegate
    } catch (e, s) {
      ErrorReporter.log('Could not load inactive location members', e, s);
    }
  }

  Widget _deviceTile(DeviceInstance device, int index, int count) {
    return GroupedListTile(
      key: ValueKey(device.id),
      position: SlicePosition.forIndex(index, count),
      hairlineInset: GroupedListTile.insetIconLeading,
      child: ListTile(
        leading: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(
            _selected.contains(device.id) ? Icons.check_circle : Icons.circle_outlined,
            color: context.appColors.appInk,
          )
        ]),
        title: Text(device.displayName),
        onTap: () => setState(() {
          _selected.contains(device.id) ? _selected.remove(device.id) : _selected.add(device.id);
          AppState().notifyListeners();
        }),
      ),
    );
  }

  Widget _buildListWidget() {
    final listed = {for (final d in AppState().devices) d.id};
    final query = filter.query.toLowerCase();
    // Not those already in the search result (an inactive favourite): keys
    // must stay unique.
    final extra = _inactiveMembers
        .where((d) => !listed.contains(d.id) && d.displayName.toLowerCase().contains(query))
        .toList(growable: false);
    final shownCount = extra.length + AppState().devices.length;
    return Stack(children: [
      ListView.builder(
        padding: Spacing.listPadding(context),
        itemCount: extra.length + AppState().devicesListItemCount,
        itemBuilder: (_, i) {
          if (i < extra.length) return _deviceTile(extra[i], i, shownCount);
          final j = i - extra.length;
          if (j >= AppState().devices.length) {
            AppState().loadDevices();
            return const SizedBox.shrink();
          }
          return _deviceTile(AppState().devices[j], i, shownCount);
        },
        findChildIndexCallback: (key) {
          final id = (key as ValueKey<String>).value;
          final e = extra.indexWhere((d) => d.id == id);
          if (e != -1) return e;
          final index = AppState().devices.indexWhere((d) => d.id == id);
          return index == -1 ? null : extra.length + index;
        },
      ),
      Positioned(
        right: 15,
        bottom: 15,
        child: _fab(),
      ),
    ]);
  }

  Widget _fab() {
    return FloatingActionButton.extended(
      onPressed: () async {
        AppState().locations[widget._stateLocationIndex].device_ids = _selected.toList();
        await LocationService.saveLocation(AppState().locations[widget._stateLocationIndex]);
        AppState().notifyListeners();
        if (!mounted) return;
        if (_delegateOpen) Navigator.pop(context, true);
        Navigator.pop(context);
      },
      backgroundColor: context.appColors.app,
      label: const Text("Save"),
      icon: const Icon(Icons.save),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, child) {
      if (state.locations.length - 1 < widget._stateLocationIndex) {
        widget._logger.w("LocationEditDevices requested for location index that is not in AppState");
        return const Center(child: DelayedCircularProgressIndicator());
      }

      final location = state.locations[widget._stateLocationIndex];
      if (!_initialized) {
        _selected.addAll(location.device_ids);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          state.searchDevices(filter);
          _loadInactiveMembers(location.device_ids.toList(growable: false));
        });
        _initialized = true;
      }

      return Scaffold(
          body: Scaffold(
        appBar: MyAppBar(location.name).getAppBar(context, [
          IconButton(
              icon: const Icon(Icons.search),
              onPressed: () async {
                _searchClosed = false;
                _delegateOpen = true;
                final willCloseThis = await showSearch(
                    context: context,
                    delegate: DevicesSearchDelegate(
                      (query) {
                        _searchChanged(query);
                        return _buildListWidget();
                      },
                      (q) => _searchChanged(q),
                    ));
                _searchClosed = true;
                _delegateOpen = false;
                _searchDebounce?.cancel();
                if (willCloseThis != true) _searchChanged("");
              }),
          ...MyAppBar.getDefaultActions(context)
        ]),
        body: state.devices.isEmpty && state.loadingDevices
            ? const Center(
                child: DelayedCircularProgressIndicator(),
              )
            : _buildListWidget(),
      ));
    });
  }
}
