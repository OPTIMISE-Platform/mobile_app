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
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/app_bar.dart';
import 'package:mobile_app/widgets/device_list_tabs/device_group.dart';
import 'package:mobile_app/widgets/device_list_tabs/device_list_item.dart';
import 'package:mobile_app/widgets/device_list_tabs/device_location.dart';
import 'package:mobile_app/widgets/device_list_tabs/device_networks.dart';
import 'package:mobile_app/widgets/device_list_tabs/favorites.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import 'device_list_tabs/device_class.dart';

class DeviceList extends StatefulWidget {
  const DeviceList({Key? key}) : super(key: key);

  @override
  State<DeviceList> createState() => DeviceListState();
}

class DeviceListState extends State<DeviceList> {
  late AppState _state;
  String _searchText = "";
  Timer? _searchDebounce;
  int _bottomBarIndex = 0;
  bool _initialized = false;

  Function? onBackCallback;
  String? customAppBarTitle;

  DeviceListState() {}

  _searchChanged(String search) {
    if (_searchText == search) {
      return;
    }
    _searchText = search;
    if (_searchDebounce?.isActive ?? false) _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _state.searchDevices(DeviceSearchFilter(search), context);
    });
  }

  Widget _buildListWidget(String query) {
    _searchChanged(query);
    if (_state.devices.isEmpty) {
      _state.loadDevices(context);
    }
    return RefreshIndicator(
      onRefresh: () => _state.refreshDevices(context),
      child: Scrollbar(
        child: _state.totalDevices == 0
            ? const Center(child: Text("No Devices"))
            : _state.totalDevices == -1
                ? Center(child: PlatformCircularProgressIndicator())
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: MyTheme.inset,
                    itemCount: _state.totalDevices,
                    itemBuilder: (context, i) {
                      if (i >= _state.devices.length) {
                        _state.loadDevices(context);
                      }
                      if (i > _state.devices.length - 1) {
                        return const SizedBox.shrink();
                      }
                      return Column(children: [
                        const Divider(),
                        DeviceListItem(i, null),
                      ]);
                    }),
      ),
    );
  }

  switchBottomBar(int i, AppState state, bool force) {
    if (_bottomBarIndex == i && !force) {
      return;
    }
    setState(() {
      customAppBarTitle = null;
      onBackCallback = null;
      _bottomBarIndex = i;
      switch (i) {
        case 5:
          state.searchDevices(DeviceSearchFilter.empty(), context);
          break;
        case 2:
          state.loadLocations(context);
          state.loadDeviceGroups(context);
          break;
        case 3:
          state.loadDeviceGroups(context);
          break;
        case 4:
          state.loadNetworks(context);
          break;
        case 0:
          state.searchDevices(DeviceSearchFilter.empty(), context, true, (e) => e.favorite);
          break;
      }
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        _state = state;
        if (!_initialized) {
          WidgetsBinding.instance?.addPostFrameCallback((_) {
            switchBottomBar(_bottomBarIndex, state, true);
          });
          _initialized = true;
        }

        List<Widget> actions = [
          PlatformWidget(
            material: (context, __) => PlatformIconButton(
                icon: Icon(PlatformIcons(context).search),
                onPressed: () {
                  showSearch(
                    context: context,
                    delegate: DevicesSearchDelegate(
                      _buildListWidget,
                      () {
                        _searchDebounce?.cancel();
                        _searchChanged("");
                      },
                      _searchChanged,
                    ),
                  );
                }),
            cupertino: (_, __) => const SizedBox.shrink(),
          ),
        ];

        if (kIsWeb) {
          actions.add(PlatformIconButton(
            onPressed: () => _state.refreshDevices(context),
            icon: const Icon(Icons.refresh),
            cupertino: (_, __) => CupertinoIconButtonData(padding: EdgeInsets.zero),
          ));
        }

        actions.addAll(MyAppBar.getDefaultActions(context));

        final appBar = MyAppBar(customAppBarTitle ?? "OPTIMISE");
        Widget? leadingAction;
        if (onBackCallback != null) {
          leadingAction = IconButton(onPressed: () => onBackCallback!(), icon: Icon(PlatformIcons(context).back));
        }

        return PlatformScaffold(
          appBar: appBar.getAppBar(context, actions, leadingAction),
          body: Column(children: [
            PlatformWidget(
                cupertino: (_, __) => Container(
                      child: CupertinoSearchTextField(
                          onChanged: (query) => _searchChanged(query), style: const TextStyle(color: Colors.black), itemColor: Colors.black),
                      padding: MyTheme.inset,
                    ),
                material: (_, __) => const SizedBox.shrink()),
            Expanded(child: (() {
              switch (_bottomBarIndex) {
                case 5:
                  return _buildListWidget(_searchText);
                case 2:
                  return const DeviceListByLocation();
                case 1:
                  return const DeviceListByDeviceClass();
                case 3:
                  return const DeviceGroupList();
                case 4:
                  return const DeviceListByNetwork();
                case 0:
                  return const DeviceListFavorites();
                default:
                  return Center(
                      child: Row(children: [
                    const Icon(
                      Icons.error,
                      color: MyTheme.errorColor,
                    ),
                    SizedBox(width: MediaQuery.of(context).textScaleFactor * 12, height: 0),
                    const Text("not implemented")
                  ], mainAxisAlignment: MainAxisAlignment.center));
              }
            })()),
          ]),
          cupertino: (context, _) => CupertinoPageScaffoldData(controller: CupertinoTabController(initialIndex: _bottomBarIndex)),
          // if not used, changes to _bottomBarIndex are not reflected visually
          bottomNavBar: _searchText != ""
              ? null
              : PlatformNavBar(items: [
                  const BottomNavigationBarItem(icon: Icon(Icons.star_border), label: "Favorites", backgroundColor: MyTheme.appColor),
                  const BottomNavigationBarItem(icon: Icon(Icons.devices), label: "Classes", backgroundColor: MyTheme.appColor),
                  BottomNavigationBarItem(icon: Icon(PlatformIcons(context).location), label: "Locations", backgroundColor: MyTheme.appColor),
                  const BottomNavigationBarItem(icon: Icon(Icons.devices_other), label: "Groups", backgroundColor: MyTheme.appColor),
                  const BottomNavigationBarItem(icon: Icon(Icons.device_hub), label: "Networks", backgroundColor: MyTheme.appColor),
                  const BottomNavigationBarItem(icon: Icon(Icons.sensors), label: "Devices", backgroundColor: MyTheme.appColor),
                ], currentIndex: _bottomBarIndex, itemChanged: (i) => switchBottomBar(i, state, false)),
        );
      },
    );
  }
}

class DevicesSearchDelegate extends SearchDelegate {
  final Widget Function(String query) _resultBuilder;
  final void Function() _onReturn;
  final void Function(String query) _onChanged;
  late final Consumer<AppState> _consumer;

  DevicesSearchDelegate(this._resultBuilder, this._onReturn, this._onChanged) {
    _consumer = Consumer<AppState>(builder: (state, __, ___) {
      return _resultBuilder(query);
    });
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return MyAppBar.getDefaultActions(context);
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return PlatformIconButton(
        onPressed: () {
          _onReturn();
          close(context, null);
        },
        cupertino: (_, __) => CupertinoIconButtonData(padding: EdgeInsets.zero),
        icon: const Icon(Icons.arrow_back));
  }

  @override
  Widget buildResults(BuildContext context) {
    _onChanged(query);
    return _consumer;
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    _onChanged(query);
    return _consumer;
  }

  @override
  ThemeData appBarTheme(BuildContext context) {
    return MyTheme.materialTheme;
  }
}
