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

import 'package:badges/badges.dart';
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

const tabFavorites = 0;
const tabClasses = 1;
const tabLocations = 2;
const tabGroups = 3;
const tabNetworks = 4;
const tabDevices = 5;

class DeviceListState extends State<DeviceList> with RestorationMixin {
  late AppState _state;
  Timer? _searchDebounce;
  int _bottomBarIndex = 0;
  bool _initialized = false;
  bool _searchClosed = false;
  final DeviceSearchFilter filter = DeviceSearchFilter.empty();

  Function? onBackCallback;
  String? customAppBarTitle;

  final _cupertinoSearchController = RestorableTextEditingController();

  DeviceListState() {}

  _searchChanged(String search, AppState state) {
    if (filter.query == search) {
      return;
    }
    if (search.isNotEmpty && _searchClosed) {
      return; // catches delayed search requests, when search has been cancelled
    }
    filter.query = search;
    if (_searchDebounce?.isActive ?? false) _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      switchBottomBar(_bottomBarIndex, state, true);
    });
  }

  Widget _buildListWidget() {
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
      if (_bottomBarIndex != i) {
        // dont overwrite on force
        customAppBarTitle = null;
        onBackCallback = null;
        _bottomBarIndex = i;
        switch (i) {
          case tabLocations:
            filter.locationIds = null;
            break;
          case tabGroups:
            filter.deviceGroupIds = null;
            break;
          case tabNetworks:
            filter.networkIds = null;
            break;
          case tabClasses:
            filter.deviceClassIds = null;
            break;
        }
      }
      switch (i) {
        case tabDevices:
          state.searchDevices(filter, context);
          break;
        case tabLocations:
          state.searchDevices(filter, context);
          break;
        case tabGroups:
          state.searchDevices(filter, context);
          break;
        case tabNetworks:
          state.searchDevices(filter, context);
          break;
        case tabFavorites:
          state.searchDevices(filter, context, true, (e) => e.favorite);
          break;
        case tabClasses:
          state.searchDevices(filter, context);
      }
    });
  }

  int _filterCount() {
    var count = (filter.locationIds ?? []).length +
        (filter.deviceGroupIds ?? []).length +
        (filter.networkIds ?? []).length +
        (filter.deviceClassIds ?? []).length;
    switch (_bottomBarIndex) {
      case tabLocations:
        count -= (filter.locationIds ?? []).length;
        break;
      case tabGroups:
        count -= (filter.deviceGroupIds ?? []).length;
        break;
      case tabNetworks:
        count -= (filter.networkIds ?? []).length;
        break;
      case tabClasses:
        count -= (filter.deviceClassIds ?? []).length;
        break;
    }
    return count;
  }

  PlatformNavBar _buildBottom(BuildContext context, AppState state) {
    return PlatformNavBar(items: [
      const BottomNavigationBarItem(icon: Icon(Icons.star_border), label: "Favorites"),
      const BottomNavigationBarItem(icon: Icon(Icons.devices), label: "Classes"),
      BottomNavigationBarItem(icon: Icon(PlatformIcons(context).location), label: "Locations"),
      const BottomNavigationBarItem(icon: Icon(Icons.devices_other), label: "Groups"),
      const BottomNavigationBarItem(icon: Icon(Icons.device_hub), label: "Networks"),
      const BottomNavigationBarItem(icon: Icon(Icons.sensors), label: "Devices"),
    ], currentIndex: _bottomBarIndex, itemChanged: (i) => switchBottomBar(i, state, false),
    material: (context, _) => MaterialNavBarData(selectedItemColor: MyTheme.appColor, unselectedItemColor: MyTheme.appColor));
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
            state.loadDeviceGroups(context);
            state.loadNetworks(context);
            state.loadLocations(context);
            switchBottomBar(_bottomBarIndex, state, true);
          });
          _initialized = true;
        }

        List<Widget> actions = [];
        if (_bottomBarIndex != tabGroups) {
          actions.add(PlatformWidget(
            material: (context, __) => PlatformIconButton(
                icon: Icon(PlatformIcons(context).search),
                onPressed: () {
                  _searchClosed = false;
                  showSearch(
                      context: context,
                      delegate: DevicesSearchDelegate(
                        (query) {
                          _searchChanged(query, state);
                          return _buildListWidget();
                        },
                        () {
                          _searchClosed = true;
                          _searchDebounce?.cancel();
                          _searchChanged("", state);
                        },
                        (q) => _searchChanged(q, state),
                      ));
                }),
            cupertino: (_, __) => const SizedBox.shrink(),
          ));
        }

        if (kIsWeb) {
          actions.add(PlatformIconButton(
            onPressed: () => _state.refreshDevices(context),
            icon: const Icon(Icons.refresh),
            cupertino: (_, __) => CupertinoIconButtonData(padding: EdgeInsets.zero),
          ));
        }
        if (_bottomBarIndex != tabGroups) {
          final List<PopupMenuOption> filterActions = [];
          if (_bottomBarIndex != tabClasses && state.deviceClasses.isNotEmpty) {
            filterActions.add(PopupMenuOption(
                label: 'Classes',
                onTap: (_) => showPlatformDialog(
                      context: context,
                      builder: (context) => PlatformAlertDialog(
                        title: const Text('Filter Classes'),
                        content: SizedBox(
                            width: double.maxFinite,
                            height: MediaQuery.of(context).size.height - MediaQuery.textScaleFactorOf(context) * 172,
                            child: Material(
                                color: const Color(0x00000000), // required for ListTile
                                child: ListView.builder(
                                    itemCount: state.deviceClasses.values.length,
                                    itemBuilder: (context, i) {
                                      final deviceClass = state.deviceClasses.values.elementAt(i);
                                      return StatefulBuilder(
                                          builder: (context, setState) => ListTile(
                                              trailing: PlatformSwitch(
                                                onChanged: (checked) {
                                                  if (checked == true) {
                                                    filter.addDeviceClass(deviceClass.id);
                                                  } else {
                                                    filter.removeDeviceClass(deviceClass.id);
                                                  }
                                                  setState(() {});
                                                },
                                                value: filter.deviceClassIds?.contains(deviceClass.id) ?? false,
                                              ),
                                              title: Text(deviceClass.name)));
                                    }))),
                        actions: <Widget>[
                          PlatformDialogAction(
                            child: const Text("OK"),
                            onPressed: () {
                              switchBottomBar(_bottomBarIndex, state, true);
                              Navigator.pop(context);
                            },
                          ),
                        ],
                      ),
                    )));
          }
          if (_bottomBarIndex != tabLocations && state.locations.isNotEmpty) {
            filterActions.add(PopupMenuOption(
                label: 'Locations',
                onTap: (_) => showPlatformDialog(
                      context: context,
                      builder: (context) => PlatformAlertDialog(
                        title: const Text('Filter Locations'),
                        content: SizedBox(
                            width: double.maxFinite,
                            height: MediaQuery.of(context).size.height - MediaQuery.textScaleFactorOf(context) * 172,
                            child: Material(
                                color: const Color(0x00000000), // required for ListTile
                                child: ListView.builder(
                                    itemCount: state.locations.length,
                                    itemBuilder: (context, i) {
                                      final location = state.locations.elementAt(i);
                                      return StatefulBuilder(
                                          builder: (context, setState) => ListTile(
                                              trailing: PlatformSwitch(
                                                onChanged: (checked) {
                                                  setState(() {
                                                    if (checked == true) {
                                                      filter.addLocation(location.id);
                                                    } else {
                                                      filter.removeLocation(location.id);
                                                    }
                                                  });
                                                },
                                                value: filter.locationIds?.contains(location.id) ?? false,
                                              ),
                                              title: Text(location.name)));
                                    }))),
                        actions: <Widget>[
                          PlatformDialogAction(
                            child: const Text("OK"),
                            onPressed: () {
                              switchBottomBar(_bottomBarIndex, state, true);
                              Navigator.pop(context);
                            },
                          ),
                        ],
                      ),
                    )));
          }
          if (_bottomBarIndex != tabGroups && state.deviceGroups.isNotEmpty) {
            filterActions.add(PopupMenuOption(
                label: 'Groups',
                onTap: (_) => showPlatformDialog(
                      context: context,
                      builder: (context) => PlatformAlertDialog(
                        title: const Text('Filter Groups'),
                        content: SizedBox(
                            width: double.maxFinite,
                            height: MediaQuery.of(context).size.height - MediaQuery.textScaleFactorOf(context) * 172,
                            child: Material(
                                color: const Color(0x00000000), // required for ListTile
                                child: ListView.builder(
                                    itemCount: state.deviceGroups.length,
                                    itemBuilder: (context, i) {
                                      final deviceGroup = state.deviceGroups.elementAt(i);
                                      return StatefulBuilder(
                                          builder: (context, setState) => ListTile(
                                              trailing: PlatformSwitch(
                                                onChanged: (checked) {
                                                  setState(() {
                                                    if (checked == true) {
                                                      filter.addDeviceGroup(deviceGroup.id);
                                                    } else {
                                                      filter.removeDeviceGroup(deviceGroup.id);
                                                    }
                                                  });
                                                },
                                                value: filter.deviceGroupIds?.contains(deviceGroup.id) ?? false,
                                              ),
                                              title: Text(deviceGroup.name)));
                                    }))),
                        actions: <Widget>[
                          PlatformDialogAction(
                            child: const Text("OK"),
                            onPressed: () {
                              switchBottomBar(_bottomBarIndex, state, true);
                              Navigator.pop(context);
                            },
                          ),
                        ],
                      ),
                    )));
          }
          if (_bottomBarIndex != tabNetworks && state.networks.isNotEmpty) {
            filterActions.add(PopupMenuOption(
                label: 'Networks',
                onTap: (_) => showPlatformDialog(
                      context: context,
                      builder: (context) => PlatformAlertDialog(
                        title: const Text('Filter Networks'),
                        content: SizedBox(
                            width: double.maxFinite,
                            height: MediaQuery.of(context).size.height - MediaQuery.textScaleFactorOf(context) * 172,
                            child: Material(
                                color: const Color(0x00000000), // required for ListTile
                                child: ListView.builder(
                                    itemCount: state.networks.length,
                                    itemBuilder: (context, i) {
                                      final network = state.networks.elementAt(i);
                                      return StatefulBuilder(
                                          builder: (context, setState) => ListTile(
                                              trailing: PlatformSwitch(
                                                onChanged: (checked) {
                                                  setState(() {
                                                    if (checked == true) {
                                                      filter.addNetwork(network.id);
                                                    } else {
                                                      filter.removeNetwork(network.id);
                                                    }
                                                  });
                                                },
                                                value: filter.networkIds?.contains(network.id) ?? false,
                                              ),
                                              title: Text(network.name)));
                                    }))),
                        actions: <Widget>[
                          PlatformDialogAction(
                            child: const Text("OK"),
                            onPressed: () {
                              switchBottomBar(_bottomBarIndex, state, true);
                              Navigator.pop(context);
                            },
                          ),
                        ],
                      ),
                    )));
          }

          final filterCount = _filterCount();
          if (filterCount > 0) {
            filterActions.add(PopupMenuOption(
                material: (context, __) => MaterialPopupMenuOptionData(
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [Divider(), Text("Reset")],
                    )),
                cupertino: (context, __) => CupertinoPopupMenuOptionData(isDestructiveAction: true),
                label: 'Reset',
                onTap: (_) {
                  if (_bottomBarIndex != tabLocations) filter.locationIds = null;
                  if (_bottomBarIndex != tabGroups) filter.deviceGroupIds = null;
                  if (_bottomBarIndex != tabNetworks) filter.networkIds = null;
                  if (_bottomBarIndex != tabClasses) filter.deviceClassIds = null;
                  switchBottomBar(_bottomBarIndex, state, true);
                }));
          }

          actions.add(PlatformPopupMenu(
            options: filterActions,
            icon: PlatformIconButton(
              icon: Badge(
                child: Icon(Icons.filter_alt, color: isCupertino(context) ? MyTheme.appColor : null),
                badgeContent: Text(filterCount.toString()),
                showBadge: filterCount > 0,
              ),
              cupertino: (_, __) => CupertinoIconButtonData(padding: EdgeInsets.zero),
              material: (_, __) => MaterialIconButtonData(disabledColor: MyTheme.textColor),
            ),
            cupertino: (context, _) => CupertinoPopupMenuData(
                title: const Text("Select Filters"),
                cancelButtonData: CupertinoPopupMenuCancelButtonData(
                  child: const Text('Close'),
                  onPressed: () => Navigator.pop(context),
                )),
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
                cupertino: _bottomBarIndex != tabGroups ? (_, __) => Container(
                      child: CupertinoSearchTextField(
                        onChanged: (query) => _searchChanged(query, state),
                        style: TextStyle(color: MyTheme.textColor),
                        itemColor: MyTheme.textColor ?? CupertinoColors.secondaryLabel,
                        restorationId: "cupertino-device-search",
                        controller: _cupertinoSearchController.value,
                      ),
                      padding: MyTheme.inset,
                    ) : null,
               ),
            Expanded(child: (() {
              switch (_bottomBarIndex) {
                case tabDevices:
                  return _buildListWidget();
                case tabLocations:
                  return const DeviceListByLocation();
                case tabClasses:
                  return const DeviceListByDeviceClass();
                case tabGroups:
                  return const DeviceGroupList();
                case tabNetworks:
                  return const DeviceListByNetwork();
                case tabFavorites:
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
          bottomNavBar: _buildBottom(context, state),
        );
      },
    );
  }

  @override
  String? get restorationId => "device_list";

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_cupertinoSearchController, "_cupertinoSearchController");
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
