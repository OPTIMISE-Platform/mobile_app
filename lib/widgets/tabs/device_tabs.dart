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
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/services/haptic_feedback_proxy.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/tabs/dashboard/dashboard.dart';
import 'package:mobile_app/widgets/tabs/devices/device_list.dart';
import 'package:mobile_app/widgets/tabs/smart-services/instances.dart';
import 'package:provider/provider.dart';

import '../shared/app_bar.dart';
import 'classes/device_class.dart';
import 'favorites/favorites.dart';
import 'groups/group_list.dart';
import 'locations/device_location.dart';
import 'networks/device_networks.dart';
import 'shared/search_delegate.dart';

class DeviceTabs extends StatefulWidget {
  const DeviceTabs({Key? key}) : super(key: key);

  @override
  State<DeviceTabs> createState() => DeviceTabsState();
}

const tabFavorites = 0;
const tabDashboard = 1;
const tabClasses = 2;
const tabLocations = 3;
const tabGroups = 4;
const tabNetworks = 5;
const tabDevices = 6;
const tabSmartServices = 7;

class DeviceTabsState extends State<DeviceTabs> with RestorationMixin {
  Timer? _searchDebounce;
  int _bottomBarIndex = 0;
  bool _initialized = false;
  bool _searchClosed = false;
  final DeviceSearchFilter filter = DeviceSearchFilter.empty();

  Function? onBackCallback;
  String? customAppBarTitle;
  bool hideSearch = false;

  bool showFab = false;
  final StreamController _fabPressedController = StreamController();
  Stream? _fabPressedControllerStream;

  Stream get fabPressed {
    if (_fabPressedControllerStream != null) {
      return _fabPressedControllerStream!;
    }
    _fabPressedControllerStream = _fabPressedController.stream.asBroadcastStream();
    return _fabPressedControllerStream!;
  }

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
      switchBottomBar(_bottomBarIndex, true);
    });
  }

  switchBottomBar(int i, bool force) {
    if (_bottomBarIndex == i && !force) {
      return;
    }
    setState(() {
      if (_bottomBarIndex != i) {
        // dont overwrite on force
        customAppBarTitle = null;
        onBackCallback = null;
        switch (_bottomBarIndex) {
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
          case tabFavorites:
            filter.favorites = null;
            break;
          case tabDashboard:
            // no-op
            break;
        }
        _bottomBarIndex = i;
      }
      switch (i) {
        case tabDevices:
          hideSearch = false;
          AppState().searchDevices(filter, context);
          showFab = false;
          break;
        case tabLocations:
          hideSearch = true;
          AppState().searchDevices(filter, context);
          showFab = true;
          break;
        case tabGroups:
          hideSearch = true;
          AppState().searchDevices(filter, context);
          showFab = true;
          break;
        case tabNetworks:
          hideSearch = true;
          AppState().searchDevices(filter, context);
          showFab = false;
          break;
        case tabFavorites:
          hideSearch = false;
          filter.favorites = true;
          AppState().searchDevices(filter, context);
          showFab = false;
          break;
        case tabClasses:
          hideSearch = true;
          AppState().searchDevices(filter, context);
          showFab = false;
          break;
        case tabSmartServices:
          hideSearch = true;
          showFab = true;
          break;
        case tabDashboard:
          hideSearch = true;
          showFab = false;
          break;
      }
    });
  }

  int _filterCount() {
    var count = (filter.locationIds ?? []).length +
        (filter.deviceGroupIds ?? []).length +
        (filter.networkIds ?? []).length +
        (filter.deviceClassIds ?? []).length;
    if (filter.favorites == true && _bottomBarIndex != tabFavorites) {
      count++;
    }
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

  PlatformNavBar _buildBottom(BuildContext context) {
    return PlatformNavBar(
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.star_border), label: "Favorites"),
          const BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: "Board"),
          const BottomNavigationBarItem(icon: Icon(Icons.devices), label: "Classes"),
          BottomNavigationBarItem(icon: Icon(PlatformIcons(context).location), label: "Locations"),
          const BottomNavigationBarItem(icon: Icon(Icons.devices_other), label: "Groups"),
          const BottomNavigationBarItem(icon: Icon(Icons.device_hub), label: "Networks"),
          const BottomNavigationBarItem(icon: Icon(Icons.sensors), label: "Devices"),
          const BottomNavigationBarItem(icon: Icon(Icons.auto_fix_high), label: "Services"),
        ],
        currentIndex: _bottomBarIndex,
        itemChanged: (i) {
          HapticFeedbackProxy.lightImpact();
          switchBottomBar(i, false);
        },
        material: (context, _) => MaterialNavBarData(selectedItemColor: MyTheme.appColor, unselectedItemColor: MyTheme.appColor));
  }

  @override
  void initState() {
    super.initState();
    if (AppState().devices.isEmpty) {
      AppState().loadDevices(context);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _fabPressedController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        if (!_initialized) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            state.loadDeviceGroups(context);
            state.loadNetworks(context);
            state.loadLocations(context);
            switchBottomBar(_bottomBarIndex, true);
          });
          _initialized = true;
        }

        List<Widget> actions = [];
        if (!hideSearch) {
          actions.add(PlatformWidget(
            material: (context, __) => PlatformIconButton(
                icon: Icon(PlatformIcons(context).search),
                onPressed: () async {
                  _searchClosed = false;
                  await showSearch(
                      context: context,
                      delegate: DevicesSearchDelegate(
                        (query) {
                          _searchChanged(query);
                          return const DeviceList();
                        },
                        (q) => _searchChanged(q),
                      ));
                  _searchClosed = true;
                  _searchDebounce?.cancel();
                  _searchChanged("");
                }),
            cupertino: (_, __) => const SizedBox.shrink(),
          ));
        }

        if (kIsWeb) {
          actions.add(PlatformIconButton(
            onPressed: () => AppState().pushRefresh(),
            icon: const Icon(Icons.refresh),
            cupertino: (_, __) => CupertinoIconButtonData(padding: EdgeInsets.zero),
          ));
        }
        if (_bottomBarIndex != tabGroups && _bottomBarIndex != tabSmartServices && _bottomBarIndex != tabDashboard) {
          // TODO move decision to showFab etc.
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
                              switchBottomBar(_bottomBarIndex, true);
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
                              switchBottomBar(_bottomBarIndex, true);
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
                              switchBottomBar(_bottomBarIndex, true);
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
                              switchBottomBar(_bottomBarIndex, true);
                              Navigator.pop(context);
                            },
                          ),
                        ],
                      ),
                    )));
          }

          if (_bottomBarIndex != tabFavorites) {
            filterActions.add(PopupMenuOption(
                label: '${filter.favorites == true ? '✓ ' : ''}Favorites',
                onTap: (_) => setState(() {
                      filter.favorites = filter.favorites == true ? null : true;
                      switchBottomBar(_bottomBarIndex, true);
                    })));
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
                  if (_bottomBarIndex != tabFavorites) filter.favorites = null;
                  switchBottomBar(_bottomBarIndex, true);
                }));
          }

          actions.add(PlatformPopupMenu(
            options: filterActions,
            icon: PlatformIconButton(
              icon: Badge(
                badgeContent: Text(filterCount.toString()),
                showBadge: filterCount > 0,
                child: Icon(Icons.filter_alt, color: isCupertino(context) ? MyTheme.appColor : null),
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

        return WillPopScope(
            onWillPop: () async {
              if (onBackCallback == null) return true;
              onBackCallback!();
              return false;
            },
            child: Scaffold(
                floatingActionButton: showFab
                    ? Container(
                        margin: const EdgeInsets.only(bottom: 55),
                        child: FloatingActionButton(
                          onPressed: () => _fabPressedController.add(null),
                          backgroundColor: MyTheme.appColor,
                          child: Icon(Icons.add, color: MyTheme.textColor),
                        ))
                    : null,
                body: PlatformScaffold(
                  appBar: appBar.getAppBar(context, actions, leadingAction),
                  body: Column(children: [
                    PlatformWidget(
                      cupertino: !hideSearch
                          ? (_, __) => Container(
                                padding: MyTheme.inset,
                                child: CupertinoSearchTextField(
                                  onChanged: (query) => _searchChanged(query),
                                  style: TextStyle(color: MyTheme.textColor),
                                  itemColor: MyTheme.textColor ?? CupertinoColors.secondaryLabel,
                                  restorationId: "cupertino-device-search",
                                  controller: _cupertinoSearchController.value,
                                ),
                              )
                          : null,
                    ),
                    Expanded(child: (() {
                      switch (_bottomBarIndex) {
                        case tabDevices:
                          return const DeviceList();
                        case tabLocations:
                          return const DeviceListByLocation();
                        case tabClasses:
                          return const DeviceListByDeviceClass();
                        case tabGroups:
                          return const GroupList();
                        case tabNetworks:
                          return const DeviceListByNetwork();
                        case tabFavorites:
                          return const DeviceListFavorites();
                        case tabSmartServices:
                          return const SmartServicesInstances();
                        case tabDashboard:
                          return const Dashboard();
                        default:
                          return Center(
                              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const Icon(
                              Icons.error,
                              color: MyTheme.errorColor,
                            ),
                            SizedBox(width: MediaQuery.of(context).textScaleFactor * 12, height: 0),
                            const Text("not implemented")
                          ]));
                      }
                    })()),
                  ]),
                  cupertino: (context, _) => CupertinoPageScaffoldData(controller: CupertinoTabController(initialIndex: _bottomBarIndex)),
                  // if not used, changes to _bottomBarIndex are not reflected visually
                  bottomNavBar: _buildBottom(context),
                )));
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
