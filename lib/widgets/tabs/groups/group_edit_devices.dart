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
import 'package:mobile_app/services/devices.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mutex/mutex.dart';
import 'package:provider/provider.dart';

import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/app_bar.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/shared/grouped_list_tile.dart';
import 'package:mobile_app/widgets/shared/paged_device_list.dart';
import 'package:mobile_app/widgets/shared/sectioned_list_view.dart';
import 'package:mobile_app/widgets/tabs/shared/search_delegate.dart';

class GroupEditDevices extends StatefulWidget {
  final DeviceGroup _group;

  const GroupEditDevices(this._group, {super.key});

  @override
  State<StatefulWidget> createState() => _GroupEditDevicesState();
}

class _GroupEditDevicesState extends State<GroupEditDevices> implements PageSource {
  final Set<String> _selected = {};
  final int _pageSize = 50;
  bool _initialized = false;
  Timer? _searchDebounce;
  bool _searchClosed = false;
  bool _delegateOpen = false;
  bool _allCandidatesLoaded = false;
  // A failed candidates page ends the list until the next search reload.
  bool _loadFailed = false;
  // Advanced after every candidates page and every search reload.
  int _pageLoads = 0;
  bool _reloading = true;
  String _query = "";
  final _m = Mutex();

  List<DeviceInstanceWithRemovesCriteria> _candidates = [];
  List<DeviceGroupCriteria> _criteria = [];
  final Map<String, DeviceInstance> _deviceCollection = {};

  @override
  bool get hasMore => !_allCandidatesLoaded;

  @override
  bool get ended => _allCandidatesLoaded || _loadFailed;

  @override
  Object get pageToken => _pageLoads;

  @override
  void loadNextPage() => unawaited(_loadMoreDevices());

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
              setState(() {
                _reloading = true;
                _loadFailed = false;
              });
              try {
                final resp = await DeviceGroupsService.getMatchingDevicesForGroup(_selected.toList(growable: false), _pageSize, 0, _query);

                _reloading = false;
                _criteria = resp.criteria;
                _candidates = resp.devices;
                _candidates.forEach((element) => _deviceCollection[element.device.id] = element.device);
                _allCandidatesLoaded = resp.devices.length < _pageSize;
              } finally {
                _pageLoads++;
              }
              setState(() {});
              AppState().notifyListeners(); // redraws SearchDelegate
        }));
  }

  /// Must not call setState before its first await: the next-page row calls
  /// it while the list builds.
  Future<void> _loadMoreDevices() async {
    if (_m.isLocked || _allCandidatesLoaded || _loadFailed) return;
    await _m.protect(() async {
      try {
        final resp = await DeviceGroupsService.getMatchingDevicesForGroup(_selected.toList(growable: false), _pageSize, _candidates.length, _query);
        _criteria = resp.criteria;
        _candidates.addAll(resp.devices);
        _candidates.forEach((element) => _deviceCollection[element.device.id] = element.device);
        _allCandidatesLoaded = resp.devices.length < _pageSize;
      } catch (e, s) {
        ErrorReporter.report('Could not load group candidates', e, s);
        _loadFailed = true;
      } finally {
        _pageLoads++;
      }
      if (!mounted) return;
      setState(() {});
      AppState().notifyListeners(); // redraws SearchDelegate
    });
  }

  /// Members missing from AppState().devices, such as inactive ones the
  /// device search hides, would otherwise be listed without a name.
  Future<void> _resolveSelectedNames() async {
    final missing = _selected.where((id) => !_deviceCollection.containsKey(id)).toList(growable: false);
    if (missing.isEmpty) return;
    try {
      for (final d in await DevicesService.getDevicesByIds(missing)) {
        _deviceCollection.putIfAbsent(d.id, () => d);
      }
    } catch (e, s) {
      ErrorReporter.log('Could not load group member names', e, s);
    }
  }

  Widget _buildListWidget() {
    return Stack(children: [
      PagedDeviceList(
        source: this,
        loading: _reloading,
        sections: [
          // A fresh group's "Selected" section is empty and so gets
          // neither a header nor an empty surface.
          ListSection<String>(
            id: "selected",
            title: "Selected",
            items: _selected.toList(),
            keyOf: (id) => id,
            itemBuilder: (context, id, position) => GroupedListTile(
              position: position,
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
            ),
          ),
          ListSection<DeviceInstanceWithRemovesCriteria>(
            id: "candidates",
            title: "Candidates",
            items: _candidates,
            keyOf: (candidate) => candidate.device.id,
            itemBuilder: (context, candidate, position) {
              return GroupedListTile(
                position: position,
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
                      _candidates.remove(candidate);
                      setState(() {});
                      AppState().notifyListeners(); // redraws SearchDelegate
                    }
                  },
                ),
              );
            },
          ),
        ],
        trailing: [
          if (!ended)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: DelayedCircularProgressIndicator()),
            ),
        ],
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
        late final List<String> deviceIds;
        late final List<DeviceGroupCriteria> criteria;
        await _m.protect(() async {
          deviceIds = _selected.toList();
          criteria = _criteria;
        });
        await DeviceGroupsService.saveDeviceGroup(widget._group, (g) {
          g.device_ids = deviceIds;
          g.criteria = criteria;
        });
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
          await Future.wait<dynamic>([_loadMoreDevices(), _resolveSelectedNames()]);
          if (!mounted) return;
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
