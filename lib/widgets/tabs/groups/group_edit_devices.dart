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

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/services/device_groups.dart';
import 'package:mutex/mutex.dart';
import 'package:provider/provider.dart';

import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/app_bar.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/tabs/shared/search_delegate.dart';

class GroupEditDevices extends StatefulWidget {
  final DeviceGroup _group;

  GroupEditDevices(this._group, {Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _GroupEditDevicesState();
}

class _GroupEditDevicesState extends State<GroupEditDevices> with RestorationMixin {
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

  final _cupertinoSearchController = RestorableTextEditingController();

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
    return Stack(children: [
      _reloading
          ? Row(children: const [Expanded(child: Center(child: DelayedCircularProgressIndicator()))])
          : ListView.builder(
              padding: MyTheme.inset,
              itemCount: _candidates.length + _selected.length + (_allCandidatesLoaded ? 0 : 1),
              itemBuilder: (_, i) {
                if (i == _candidates.length + _selected.length - 1 && !_allCandidatesLoaded) {
                  _loadMoreDevices();
                  return Row(children: const [Expanded(child: Center(child: DelayedCircularProgressIndicator()))]);
                }
                if (i > _candidates.length + _selected.length - 1) {
                  return const SizedBox.shrink();
                }
                return Column(
                  children: [
                    i > 0 ? const Divider() : const SizedBox.shrink(),
                    i < _selected.length
                        ? ListTile(
                            leading: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(
                                PlatformIcons(context).checkMarkCircledSolid,
                                color: MyTheme.appColor,
                              )
                            ]),
                            title: Text(_deviceCollection[_selected.elementAt(i)]?.displayName ?? "MISSING_DEVICE_NAME"),
                            onTap: () {
                              _selected.remove(_selected.elementAt(i));
                              _searchChanged(_query, true);
                            },
                          )
                        : ListTile(
                            leading: Column(mainAxisAlignment: MainAxisAlignment.center, children: const [
                              Icon(
                                Icons.circle_outlined,
                                color: MyTheme.appColor,
                              )
                            ]),
                            title: Text(_candidates[i - _selected.length].device.displayName),
                            onTap: () async {
                              if (_candidates[i - _selected.length].removesCriteria || _criteria.isEmpty) {
                                setState(() => _reloading = true);
                                _selected.add(_candidates[i - _selected.length].device.id);
                                _searchChanged(_query, true);
                                await _m.protect(() async {});
                                setState(() => _reloading = false);
                                AppState().notifyListeners(); // redraws SearchDelegate
                              } else {
                                _selected.add(_candidates[i - _selected.length].device.id);
                                _candidates.removeAt(i - _selected.length + 1); // +1 because already added the element to _selected
                                setState(() {});
                                AppState().notifyListeners(); // redraws SearchDelegate
                              }
                            },
                          ),
                  ],
                );
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
        Navigator.pop(context);
      },
      backgroundColor: MyTheme.appColor,
      label: Text("Save", style: TextStyle(color: MyTheme.textColor)),
      icon: Icon(Icons.save, color: MyTheme.textColor),
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
          body: PlatformScaffold(
        appBar: MyAppBar(deviceGroup.name).getAppBar(context, [
          PlatformWidget(
            material: (context, __) => PlatformIconButton(
                icon: Icon(PlatformIcons(context).search),
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
            cupertino: (_, __) => const SizedBox.shrink(),
          ),
          ...MyAppBar.getDefaultActions(context)
        ]),
        body: _reloading
            ? Center(
                child: const DelayedCircularProgressIndicator(),
              )
            : Column(children: [
                PlatformWidget(
                  cupertino: (_, __) => Container(
                    padding: MyTheme.inset,
                    child: CupertinoSearchTextField(
                      onChanged: (query) => _searchChanged(query, false),
                      style: TextStyle(color: MyTheme.textColor),
                      itemColor: MyTheme.textColor ?? CupertinoColors.secondaryLabel,
                      restorationId: "cupertino-device-search",
                      controller: _cupertinoSearchController.value,
                    ),
                  ),
                ),
                Expanded(child: _buildListWidget())
              ]),
      ));
    });
  }

  @override
  String? get restorationId => "GroupEditDevices";

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_cupertinoSearchController, "_cupertinoSearchController");
  }
}
