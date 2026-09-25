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
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/services/device_groups.dart';
import 'package:mutex/mutex.dart';
import 'package:provider/provider.dart';

import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/app_bar.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/shared/grouped_list_tile.dart';
import 'package:mobile_app/widgets/shared/section_list_header.dart';
import 'package:mobile_app/widgets/shared/slice_position.dart';
import 'package:mobile_app/widgets/tabs/shared/search_delegate.dart';

class GroupEditDevices extends StatefulWidget {
  final DeviceGroup _group;

  const GroupEditDevices(this._group, {super.key});

  @override
  State<StatefulWidget> createState() => _GroupEditDevicesState();
}

class _GroupEditDevicesState extends State<GroupEditDevices> {
  final Set<String> _selected = {};
  final int _pageSize = 50;
  bool _initialized = false;
  Timer? _searchDebounce;
  bool _searchClosed = false;
  bool _delegateOpen = false;
  bool _allCandidatesLoaded = false;
  bool _reloading = true;
  String _query = "";
  final _m = Mutex();

  List<DeviceInstanceWithRemovesCriteria> _candidates = [];
  List<DeviceGroupCriteria> _criteria = [];
  final Map<String, DeviceInstance> _deviceCollection = {};

  _searchChanged(String search, bool force) {
    if (_query == search && !force) {
      return;
    }
    if (search.isNotEmpty && _searchClosed) {
      return; // catches delayed search requests, when search has been cancelled
    }
    _query = search;
    if (_searchDebounce?.isActive ?? false) _searchDebounce?.cancel();
    _searchDebounce = Timer(
        Duration(milliseconds: force ? 0 : 300),
        () async => await _m.protect(() async {
              setState(() => _reloading = true);
              final resp = await DeviceGroupsService.getMatchingDevicesForGroup(_selected.toList(growable: false), _pageSize, 0, _query);

              _reloading = false;
              _criteria = resp.criteria;
              _candidates = resp.devices;
              _candidates.forEach((element) => _deviceCollection[element.device.id] = element.device);
              _allCandidatesLoaded = resp.devices.length < _pageSize;
              setState(() {});
              AppState().notifyListeners(); // redraws SearchDelegate
        }));
  }

  _loadMoreDevices() async {
    if (_m.isLocked || _allCandidatesLoaded) return;
    await _m.protect(() async {
      setState(() {});
      final resp = await DeviceGroupsService.getMatchingDevicesForGroup(_selected.toList(growable: false), _pageSize, _candidates.length, _query);
      _criteria = resp.criteria;
      _candidates.addAll(resp.devices);
      _candidates.forEach((element) => _deviceCollection[element.device.id] = element.device);
      _allCandidatesLoaded = resp.devices.length < _pageSize;
      setState(() {});
      AppState().notifyListeners(); // redraws SearchDelegate
    });
  }

  Widget _buildListWidget() {
    final selectedCount = _selected.length;
    final candidateCount = _candidates.length;
    // Each section's header only shows while it has a row - a fresh group's
    // "Selected" section is empty, and never gets an empty surface.
    final headerCount = (selectedCount > 0 ? 1 : 0) + (candidateCount > 0 ? 1 : 0);

    return Stack(children: [
      _reloading
          ? const Row(children: [Expanded(child: Center(child: DelayedCircularProgressIndicator()))])
          : ListView.builder(
              padding: Spacing.insetVertical,
              itemCount: selectedCount +
                  candidateCount +
                  headerCount +
                  (_allCandidatesLoaded ? 0 : 1),
              itemBuilder: (context, i) {
                if (selectedCount > 0) {
                  if (i == 0) return const SectionListHeader("Selected");
                  i -= 1;
                }
                if (i < selectedCount) {
                  final id = _selected.elementAt(i);
                  return GroupedListTile(
                    key: ValueKey("selected-$id"),
                    position: SlicePosition.forIndex(i, selectedCount),
                    hairlineInset: GroupedListTile.insetIconLeading,
                    child: ListTile(
                      leading: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(
                          Icons.check_circle,
                          color: context.appColors.appInk,
                        )
                      ]),
                      title: Text(_deviceCollection[id]?.displayName ?? "MISSING_DEVICE_NAME"),
                      onTap: () {
                        _selected.remove(id);
                        _searchChanged(_query, true);
                      },
                    ),
                  );
                }
                i -= selectedCount;
                if (candidateCount > 0) {
                  if (i == 0) return const SectionListHeader("Candidates");
                  i -= 1;
                }
                if (i == candidateCount - 1 && !_allCandidatesLoaded) {
                  _loadMoreDevices();
                  return GroupedListTile(
                    position: SlicePosition.forIndex(i, candidateCount),
                    child: const Row(children: [Expanded(child: Center(child: DelayedCircularProgressIndicator()))]),
                  );
                }
                if (i > candidateCount - 1) {
                  return const SizedBox.shrink();
                }
                final candidate = _candidates[i];
                return GroupedListTile(
                  key: ValueKey("candidate-${candidate.device.id}"),
                  position: SlicePosition.forIndex(i, candidateCount),
                  hairlineInset: GroupedListTile.insetIconLeading,
                  child: ListTile(
                    leading: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(
                        Icons.circle_outlined,
                        color: context.appColors.appInk,
                      )
                    ]),
                    title: Text(candidate.device.displayName),
                    onTap: () async {
                      if (candidate.removesCriteria || _criteria.isEmpty) {
                        setState(() => _reloading = true);
                        _selected.add(candidate.device.id);
                        _searchChanged(_query, true);
                        await _m.protect(() async {});
                        setState(() => _reloading = false);
                        AppState().notifyListeners(); // redraws SearchDelegate
                      } else {
                        _selected.add(candidate.device.id);
                        _candidates.removeAt(i);
                        setState(() {});
                        AppState().notifyListeners(); // redraws SearchDelegate
                      }
                    },
                  ),
                );
              },
              findChildIndexCallback: (key) {
                final id = (key as ValueKey<String>).value;
                final selectedHeader = selectedCount > 0 ? 1 : 0;
                if (id.startsWith("selected-")) {
                  final deviceId = id.substring("selected-".length);
                  final idx = _selected.toList().indexOf(deviceId);
                  return idx == -1 ? null : selectedHeader + idx;
                }
                final deviceId = id.substring("candidate-".length);
                final idx = _candidates.indexWhere((c) => c.device.id == deviceId);
                if (idx == -1) return null;
                final candidateHeader = candidateCount > 0 ? 1 : 0;
                return selectedHeader + selectedCount + candidateHeader + idx;
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
        await _m.protect(() async {
          widget._group.device_ids = _selected.toList();
          widget._group.criteria = _criteria;
        });
        await DeviceGroupsService.saveDeviceGroup(widget._group);
        AppState().notifyListeners();
        if (_delegateOpen && mounted) Navigator.pop(context, true);
        if (!mounted) return;
        Navigator.pop(context);
      },
      backgroundColor: context.appColors.app,
      label: const Text("Save"),
      icon: const Icon(Icons.save),
    );
  }

  @override
  void initState() {
    super.initState();
    AppState().devices.map((e) => _deviceCollection[e.id] = e);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, child) {
      final deviceGroup = widget._group;
      if (!_initialized) {
        AppState().devices.forEach((element) => _deviceCollection[element.id] = element);
        _selected.addAll(deviceGroup.device_ids);
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await _loadMoreDevices();
          setState(() {
            _reloading = false;
          });
        });
        _initialized = true;
      }

      return Scaffold(
          body: Scaffold(
        appBar: MyAppBar(deviceGroup.name).getAppBar(context, [
          IconButton(
              icon: const Icon(Icons.search),
              onPressed: () async {
                _searchClosed = false;
                _delegateOpen = true;
                final willCloseThis = await showSearch(
                    context: context,
                    delegate: DevicesSearchDelegate(
                      (query) {
                        _searchChanged(query, false);
                        return _buildListWidget();
                      },
                      (q) => _searchChanged(q, false),
                    ));
                _searchClosed = true;
                _delegateOpen = false;
                _searchDebounce?.cancel();
                if (willCloseThis != true) _searchChanged("", false);
              }),
          ...MyAppBar.getDefaultActions(context)
        ]),
        body: _reloading
            ? const Center(
                child: DelayedCircularProgressIndicator(),
              )
            : _buildListWidget(),
      ));
    });
  }
}
