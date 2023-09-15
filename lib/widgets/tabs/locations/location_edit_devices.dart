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
import 'package:logger/logger.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/services/locations.dart';
import 'package:provider/provider.dart';

import '../../../app_state.dart';
import '../../../theme.dart';
import '../../shared/app_bar.dart';
import '../../shared/delay_circular_progress_indicator.dart';
import '../shared/search_delegate.dart';

class LocationEditDevices extends StatefulWidget {
  final int _stateLocationIndex;
  final _logger = Logger(
    printer: SimplePrinter(),
  );

  LocationEditDevices(this._stateLocationIndex, {Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _LocationEditDevicesState();
}

class _LocationEditDevicesState extends State<LocationEditDevices> with RestorationMixin {
  final Set<String> _selected = {};
  bool _initialized = false;
  Timer? _searchDebounce;
  bool _searchClosed = false;
  bool _delegateOpen = false;

  DeviceSearchFilter filter = DeviceSearchFilter("");

  final _cupertinoSearchController = RestorableTextEditingController();

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
      AppState().searchDevices(filter, context);
    });
  }

  Widget _buildListWidget() {
    return Stack(children: [
      ListView.builder(
        padding: MyTheme.inset,
        itemCount: AppState().totalDevices,
        itemBuilder: (_, i) {
          if (i >= AppState().devices.length) {
            AppState().loadDevices(context);
          }
          if (i > AppState().devices.length - 1) {
            return const SizedBox.shrink();
          }
          return Column(
            children: [
              i > 0 ? const Divider() : const SizedBox.shrink(),
              ListTile(
                leading: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(
                    _selected.contains(AppState().devices[i].id) ? PlatformIcons(context).checkMarkCircledSolid : Icons.circle_outlined,
                    color: MyTheme.appColor,
                  )
                ]),
                title: Text(AppState().devices[i].displayName),
                onTap: () => setState(() {
                  _selected.contains(AppState().devices[i].id) ? _selected.remove(AppState().devices[i].id) : _selected.add(AppState().devices[i].id);
                  AppState().notifyListeners();
                }),
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
        AppState().locations[widget._stateLocationIndex].device_ids = _selected.toList();
        await LocationService.saveLocation(AppState().locations[widget._stateLocationIndex]);
        AppState().notifyListeners();
        if (_delegateOpen) Navigator.pop(context, true);
        Navigator.pop(context);
      },
      backgroundColor: MyTheme.appColor,
      label: Text("Save", style: TextStyle(color: MyTheme.textColor)),
      icon: Icon(Icons.save, color: MyTheme.textColor),
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
          state.searchDevices(filter, context);
        });
        _initialized = true;
      }

      return Scaffold(
          body: PlatformScaffold(
        appBar: MyAppBar(location.name).getAppBar(context, [
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
            cupertino: (_, __) => const SizedBox.shrink(),
          ),
          ...MyAppBar.getDefaultActions(context)
        ]),
        body: state.devices.isEmpty && state.loadingDevices
            ? const Center(
                child: DelayedCircularProgressIndicator(),
              )
            : Column(children: [
                PlatformWidget(
                  cupertino: (_, __) => Container(
                    padding: MyTheme.inset,
                    child: CupertinoSearchTextField(
                      onChanged: (query) => _searchChanged(query),
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
  String? get restorationId => "LocationEditDevices";

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_cupertinoSearchController, "_cupertinoSearchController");
  }
}
