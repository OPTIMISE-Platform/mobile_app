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
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/services/device_classes.dart';
import 'package:mobile_app/services/device_groups.dart';
import 'package:mobile_app/services/haptic_feedback_proxy.dart';
import 'package:mobile_app/services/locations.dart';
import 'package:mobile_app/services/networks.dart';
import 'package:mobile_app/services/smart_service.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/tabs/dashboard/dashboard.dart';
import 'package:mobile_app/widgets/tabs/devices/device_list.dart';
import 'package:mobile_app/widgets/tabs/gateways/gateways.dart';
import 'package:mobile_app/widgets/tabs/nav.dart';
import 'package:mobile_app/widgets/tabs/smart-services/instances.dart';
import 'package:provider/provider.dart';

import 'package:mobile_app/widgets/shared/app_bar.dart';
import 'package:mobile_app/widgets/tabs/classes/device_class.dart';
import 'package:mobile_app/widgets/tabs/favorites/favorites.dart';
import 'package:mobile_app/widgets/tabs/groups/group_list.dart';
import 'package:mobile_app/widgets/tabs/locations/device_location.dart';
import 'package:mobile_app/widgets/tabs/networks/device_networks.dart';
import 'package:mobile_app/widgets/tabs/shared/search_delegate.dart';
import 'package:sidebarx/sidebarx.dart';

import '../../services/settings.dart';

class DeviceTabs extends StatefulWidget {
  const DeviceTabs({Key? key}) : super(key: key);

  @override
  State<DeviceTabs> createState() => DeviceTabsState();
}

class DeviceTabsState extends State<DeviceTabs> with RestorationMixin {
  Timer? _searchDebounce;
  int _bottomBarIndex = 0;
  int _navigationIndex = 0;
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
    _fabPressedControllerStream =
        _fabPressedController.stream.asBroadcastStream();
    return _fabPressedControllerStream!;
  }

  final _cupertinoSearchController = RestorableTextEditingController();

  final controller = CupertinoTabController(initialIndex: 0);

  final _sidebarController =
      SidebarXController(selectedIndex: 0, extended: true);

  final _tabKeys = [
    GlobalKey(),
    GlobalKey(),
    GlobalKey(),
    GlobalKey(),
    GlobalKey(),
    GlobalKey(),
    GlobalKey(),
    GlobalKey(),
    GlobalKey()
  ];

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
      switchScreen(_navigationIndex, true);
    });
  }

  switchScreen(int selectedIndex, bool force) {
    if (_navigationIndex == selectedIndex && !force) {
      return;
    }
    setState(() {
      if (_navigationIndex != selectedIndex) {
        // dont overwrite on force
        customAppBarTitle = null;
        onBackCallback = null;
        switch (_navigationIndex) {
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
          case tabDevices:
            filter.favorites = null;
            break;
          case tabDashboard:
            // no-op
            break;
        }
        _navigationIndex = selectedIndex;
      }
      switch (selectedIndex) {
        case tabFavorites:
          hideSearch = false;
          AppState().searchDevices(filter, context);
          showFab = false;
          break;
        case tabDashboard:
          hideSearch = true;
          showFab = false;
          break;
        case tabDevices:
          hideSearch = false;
          AppState().searchDevices(filter, context);
          showFab = false;
          break;
        case tabLocations:
          hideSearch = true;
          AppState().searchDevices(filter, context);
          showFab = LocationService.isCreateEditDeleteAvailable();
          break;
        case tabGroups:
          hideSearch = true;
          AppState().searchDevices(filter, context);
          showFab = DeviceGroupsService.isCreateEditDeleteAvailable();
          break;
        case tabNetworks:
          hideSearch = true;
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
        case tabGateways:
          hideSearch = true;
          showFab = true;
          break;
      }
    });
  }

  List<bool> _tabDisabled() {
    final state = AppState();
    return [
      false,
      !SmartServiceService.isAvailable(),
      state.deviceClasses.isEmpty && !DeviceClassesService.isAvailable(),
      state.locations.isEmpty && !LocationService.isListAvailable(),
      state.deviceGroups.isEmpty && !DeviceGroupsService.isListAvailable(),
      state.networks.isEmpty && !NetworksService.isAvailable(),
      false,
      !SmartServiceService.isAvailable(),
      false
    ];
  }

  /// create BottomNavigationBar with items
  PlatformNavBar _buildBottom(BuildContext context) {
    final disabled = _tabDisabled();

    Color disabledColor;
    if (isCupertino(context)) {
      disabledColor = Theme.of(context).disabledColor.withAlpha(32);
    } else {
      disabledColor = Theme.of(context).disabledColor;
    }

    final List<BottomNavigationBarItem> bottomBarItems = [];

    if (Platform.isIOS) {
      navItems.forEach((navItem) {
        bottomBarItems.add(BottomNavigationBarItem(
            tooltip: disabled[navItem.index] ? "Currently unavailable" : null,
            icon: Icon(navItem.icon,
                key: _tabKeys[navItem.index],
                color: disabled[navItem.index] ? disabledColor : null),
            label: navItem.name));
      });
    } else {
      navItems.forEach((navItem) {
        if (["Favorites", "Dashboard"].contains(navItem.name)) {
          bottomBarItems.add(BottomNavigationBarItem(
              tooltip: disabled[navItem.index] ? "Currently unavailable" : null,
              icon: Icon(navItem.icon,
                  key: _tabKeys[navItem.index],
                  color: disabled[navItem.index] ? disabledColor : null),
              label: navItem.name));
        }
      });
    }

    return PlatformNavBar(
        items: bottomBarItems,
        currentIndex: _bottomBarIndex,
        itemChanged: (i) {
          if (disabled[i]) {
            controller.index = _bottomBarIndex;
            return;
          }
          setState(() {
            _bottomBarIndex = i;
            _navigationIndex = i;
            _sidebarController.selectIndex(i);
          });
          HapticFeedbackProxy.lightImpact();
          switchScreen(i, false);
        },
    );
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
    _cupertinoSearchController.dispose();
    _sidebarController.dispose();
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
            switchScreen(_bottomBarIndex, true);
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
            cupertino: (_, __) =>
                CupertinoIconButtonData(padding: EdgeInsets.zero),
          ));
        }


        if (Settings.getFilterMode()){
          populateAndShowFilterMenu(state, context, actions);
        }
        actions.addAll(MyAppBar.getDefaultActions(context));

        final appBar = MyAppBar(customAppBarTitle ?? "");
        Widget? leadingAction;
        if (onBackCallback != null) {
          leadingAction = IconButton(
              onPressed: () => onBackCallback!(),
              icon: Icon(PlatformIcons(context).back));
        }

        final List<SidebarXItem> sidebarItems = [];

        navItems.forEach((navItem) {
          sidebarItems.add(SidebarXItem(

              icon: navItem.icon,
              label: navItem.name,
              onTap: () {
                setState(() {
                  _navigationIndex = navItem.index;
                  switchScreen(_navigationIndex, true);
                  Navigator.pop(context);
                });
              }));
        });

        var textColor = MyTheme.textColor;
        var selectorColor = Colors.teal.shade50;
        var iconColor = MyTheme.appColor;
        var backgroundColor = Colors.white;

        if (MyTheme.isDarkMode) {
            selectorColor = MyTheme.appColor;
            iconColor = Colors.white;
            backgroundColor = const Color(0xFF424242);
        }

        final divider = Divider(color: textColor?.withOpacity(0.3), height: 1);

        final drawer = SidebarX(
          controller: _sidebarController,
          extendedTheme: const SidebarXTheme(
            width: 200,
            margin: EdgeInsets.only(right: 10),
          ),
          items: sidebarItems,
          headerDivider: divider,
          footerDivider: divider,
          headerBuilder: (context, extended) {
            return SafeArea(
              child: SizedBox(
                height: 100,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Image.asset('assets/icon/icon.png'),
                ),
              ),
            );
          },
          theme: SidebarXTheme(
            decoration: BoxDecoration(
              color: backgroundColor,
            ),
            textStyle: TextStyle(color: textColor),
            selectedTextStyle: TextStyle(color: textColor),
            itemTextPadding: const EdgeInsets.only(left: 30),
            selectedItemTextPadding: const EdgeInsets.only(left: 30),
            selectedItemDecoration: BoxDecoration(
              color: selectorColor,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(10),
                bottomRight: Radius.circular(10),
                topLeft: Radius.circular(10),
                bottomLeft: Radius.circular(10),
              ),
            ),
            selectedIconTheme: IconThemeData(color: iconColor),
            iconTheme: IconThemeData(
              color: iconColor,
              size: 20,
            ),
          ),
        );

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
                body: Theme(
                    data: Theme.of(context).copyWith(
                        splashFactory: _getCustomSplashFactory(context),
                        highlightColor: Colors.transparent),
                    child: PlatformScaffold(
                      material: (_, __) => MaterialScaffoldData(
                        drawer: drawer,
                      ),
                      appBar: appBar.getAppBar(context, actions, leadingAction),
                      body: Column(children: [
                        PlatformWidget(
                          cupertino: !hideSearch
                              ? (_, __) => Container(
                                    padding: MyTheme.inset,
                                    child: CupertinoSearchTextField(
                                      onChanged: (query) =>
                                          _searchChanged(query),
                                      style:
                                          TextStyle(color: MyTheme.textColor),
                                      itemColor: MyTheme.textColor ??
                                          CupertinoColors.secondaryLabel,
                                      restorationId: "cupertino-device-search",
                                      controller:
                                          _cupertinoSearchController.value,
                                    ),
                                  )
                              : null,
                        ),
                        Expanded(child: (() {
                          switch (_navigationIndex) {
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
                            case tabGateways:
                              return const Gateways();
                            default:
                              return Center(
                                  child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                    const Icon(
                                      Icons.error,
                                      color: MyTheme.errorColor,
                                    ),
                                    SizedBox(
                                        width: MediaQuery.of(context)
                                                .textScaleFactor *
                                            12,
                                        height: 0),
                                    const Text("not implemented")
                                  ]));
                          }
                        })()),
                      ]),
                      cupertino: (context, _) =>
                          CupertinoPageScaffoldData(controller: controller),
                      // if not used, changes to _bottomBarIndex are not reflected visually
                      bottomNavBar: _buildBottom(context),
                    ))));
      },
    );
  }

  /// Populate and show filter menu
  /// uncomment to disable
  void populateAndShowFilterMenu(AppState state, BuildContext context, List<Widget> actions) {
    if (_navigationIndex != tabGroups &&
        _navigationIndex != tabSmartServices &&
        _navigationIndex != tabDashboard) {
      // TODO move decision to showFab etc.

      final filterOkAction = PlatformDialogAction(
        child: const Text("OK"),
        onPressed: () {
          switchScreen(_navigationIndex, true);
          Navigator.pop(context);
        },
      );

      final List<PopupMenuOption> filterActions = [];
      if (_navigationIndex != tabClasses && state.deviceClasses.isNotEmpty) {
        filterActions.add(PopupMenuOption(
            label: '${filter.deviceClassIds != null ? '✓ ' : ''}Classes',
            onTap: (_) => showPlatformDialog(
                  context: context,
                  builder: (context) => PlatformAlertDialog(
                    title: const Text('Filter Classes'),
                    content: SizedBox(
                        width: double.maxFinite,
                        height: MediaQuery.of(context).size.height -
                            MediaQuery.textScaleFactorOf(context) * 172,
                        child: Material(
                            color: const Color(0x00000000),
                            // required for ListTile
                            child: ListView.builder(
                                itemCount:
                                    state.deviceClasses.values.length,
                                itemBuilder: (context, i) {
                                  final deviceClass = state
                                      .deviceClasses.values
                                      .elementAt(i);
                                  return StatefulBuilder(
                                      builder: (context, setState) =>
                                          ListTile(
                                              trailing: PlatformSwitch(
                                                onChanged: (checked) {
                                                  if (checked == true) {
                                                    filter.addDeviceClass(
                                                        deviceClass.id);
                                                  } else {
                                                    filter
                                                        .removeDeviceClass(
                                                            deviceClass.id);
                                                  }
                                                  setState(() {});
                                                },
                                                value: filter.deviceClassIds
                                                        ?.contains(
                                                            deviceClass
                                                                .id) ??
                                                    false,
                                              ),
                                              title:
                                                  Text(deviceClass.name)));
                                }))),
                    actions: <Widget>[
                      filterOkAction
                    ],
                  ),
                )));
      }
      if (_navigationIndex != tabLocations && state.locations.isNotEmpty) {
        filterActions.add(PopupMenuOption(
            label: '${filter.locationIds != null ? '✓ ' : ''}Locations',
            onTap: (_) => showPlatformDialog(
                  context: context,
                  builder: (context) => PlatformAlertDialog(
                    title: const Text('Filter Locations'),
                    content: SizedBox(
                        width: double.maxFinite,
                        height: MediaQuery.of(context).size.height -
                            MediaQuery.textScaleFactorOf(context) * 172,
                        child: Material(
                            color: const Color(0x00000000),
                            // required for ListTile
                            child: ListView.builder(
                                itemCount: state.locations.length,
                                itemBuilder: (context, i) {
                                  final location =
                                      state.locations.elementAt(i);
                                  return StatefulBuilder(
                                      builder: (context, setState) =>
                                          ListTile(
                                              trailing: PlatformSwitch(
                                                onChanged: (checked) {
                                                  setState(() {
                                                    if (checked == true) {
                                                      filter.addLocation(
                                                          location.id);
                                                    } else {
                                                      filter.removeLocation(
                                                          location.id);
                                                    }
                                                  });
                                                },
                                                value: filter.locationIds
                                                        ?.contains(
                                                            location.id) ??
                                                    false,
                                              ),
                                              title: Text(location.name)));
                                }))),
                    actions: <Widget>[
                      filterOkAction
                    ],
                  ),
                )));
      }
      if (_navigationIndex != tabGroups && state.deviceGroups.isNotEmpty) {
        filterActions.add(PopupMenuOption(
            label: '${filter.deviceGroupIds != null ? '✓ ' : ''}Groups',
            onTap: (_) => showPlatformDialog(
                  context: context,
                  builder: (context) => PlatformAlertDialog(
                    title: const Text('Filter Groups'),
                    content: SizedBox(
                        width: double.maxFinite,
                        height: MediaQuery.of(context).size.height -
                            MediaQuery.textScaleFactorOf(context) * 172,
                        child: Material(
                            color: const Color(0x00000000),
                            // required for ListTile
                            child: ListView.builder(
                                itemCount: state.deviceGroups.length,
                                itemBuilder: (context, i) {
                                  final deviceGroup =
                                      state.deviceGroups.elementAt(i);
                                  return StatefulBuilder(
                                      builder: (context, setState) =>
                                          ListTile(
                                              trailing: PlatformSwitch(
                                                onChanged: (checked) {
                                                  setState(() {
                                                    if (checked == true) {
                                                      filter.addDeviceGroup(
                                                          deviceGroup.id);
                                                    } else {
                                                      filter
                                                          .removeDeviceGroup(
                                                              deviceGroup
                                                                  .id);
                                                    }
                                                  });
                                                },
                                                value: filter.deviceGroupIds
                                                        ?.contains(
                                                            deviceGroup
                                                                .id) ??
                                                    false,
                                              ),
                                              title:
                                                  Text(deviceGroup.name)));
                                }))),
                    actions: <Widget>[
                      filterOkAction
                    ],
                  ),
                )));
      }
      if (_navigationIndex != tabNetworks && state.networks.isNotEmpty) {
        filterActions.add(PopupMenuOption(
            label: '${filter.networkIds != null ? '✓ ' : ''}Networks',
            onTap: (_) => showPlatformDialog(
                  context: context,
                  builder: (context) => PlatformAlertDialog(
                    title: const Text('Filter Networks'),
                    content: SizedBox(
                        width: double.maxFinite,
                        height: MediaQuery.of(context).size.height -
                            MediaQuery.textScaleFactorOf(context) * 172,
                        child: Material(
                            color: const Color(0x00000000),
                            // required for ListTile
                            child: ListView.builder(
                                itemCount: state.networks.length,
                                itemBuilder: (context, i) {
                                  final network =
                                      state.networks.elementAt(i);
                                  return StatefulBuilder(
                                      builder: (context, setState) =>
                                          ListTile(
                                              trailing: PlatformSwitch(
                                                onChanged: (checked) {
                                                  setState(() {
                                                    if (checked == true) {
                                                      filter.addNetwork(
                                                          network.id);
                                                    } else {
                                                      filter.removeNetwork(
                                                          network.id);
                                                    }
                                                  });
                                                },
                                                value: filter.networkIds
                                                        ?.contains(
                                                            network.id) ??
                                                    false,
                                              ),
                                              title: Text(network.name)));
                                }))),
                    actions: <Widget>[
                      filterOkAction
                    ],
                  ),
                )));
      }

      if (_navigationIndex != tabFavorites) {
        filterActions.add(PopupMenuOption(
            label: '${filter.favorites == true ? '✓ ' : ''}Favorites',
            onTap: (_) => setState(() {
                  filter.favorites = filter.favorites == true ? null : true;
                  switchScreen(_navigationIndex, true);
                })));
      }

      addFilterMenuResetOption(filterActions, actions, context);
    }
  }

  /*
   * Add a reset option to the filter menu
   */
  void addFilterMenuResetOption(List<PopupMenuOption> filterActions,
      List<Widget> actions, BuildContext context) {
    final filterCount = _filterCount();
    if (filterCount > 0) {
      filterActions.add(PopupMenuOption(
          material: (context, __) => MaterialPopupMenuOptionData(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [Divider(), Text("Reset")],
              )),
          cupertino: (context, __) =>
              CupertinoPopupMenuOptionData(isDestructiveAction: true),
          label: 'Reset',
          onTap: (_) {
            if (_navigationIndex != tabLocations) {
              filter.locationIds = null;
            }
            if (_navigationIndex != tabGroups) {
              filter.deviceGroupIds = null;
            }
            if (_navigationIndex != tabNetworks) filter.networkIds = null;
            if (_navigationIndex != tabClasses) {
              filter.deviceClassIds = null;
            }
            if (_navigationIndex != tabFavorites) filter.favorites = null;
            switchScreen(_navigationIndex, true);
          }));
    }

    actions.add(PlatformPopupMenu(
      options: filterActions,
      icon: Badge(
        label: Text(filterCount.toString()),
        isLabelVisible: filterCount > 0,
        textColor: Colors.white,
        child: Icon(Icons.filter_alt,
            color: isCupertino(context) ? MyTheme.appColor : null),
      ),
      cupertino: (context, _) => CupertinoPopupMenuData(
          title: const Text("Select Filters"),
          cancelButtonData: CupertinoPopupMenuCancelButtonData(
            child: const Text('Close'),
            onPressed: () => Navigator.pop(context),
          )),
    ));
  }

  /// Returns the number of filters that are currently active
  int _filterCount() {
    var count = (filter.locationIds ?? []).length +
        (filter.deviceGroupIds ?? []).length +
        (filter.networkIds ?? []).length +
        (filter.deviceClassIds ?? []).length;
    if (filter.favorites == true && _navigationIndex != tabFavorites) {
      count++;
    }
    switch (_navigationIndex) {
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

  @override
  String? get restorationId => "device_list";


  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(
        _cupertinoSearchController, "_cupertinoSearchController");
  }

  InteractiveInkFeatureFactory _getCustomSplashFactory(BuildContext context) {
    return _CustomInkSplashFactory()
      ..keys = _tabKeys
      ..keysDisabled = _tabDisabled();
  }
}

class _CustomInkSplashFactory extends InteractiveInkFeatureFactory {
  List<GlobalKey> keys = [];
  List<bool> keysDisabled = [];

  @override
  InteractiveInkFeature create(
      {required MaterialInkController controller,
      required RenderBox referenceBox,
      required Offset position,
      required Color color,
      required TextDirection textDirection,
      bool containedInkWell = false,
      RectCallback? rectCallback,
      BorderRadius? borderRadius,
      ShapeBorder? customBorder,
      double? radius,
      VoidCallback? onRemoved}) {
    return _CustomInkSplash(
      controller: controller,
      referenceBox: referenceBox,
      position: position,
      color: color,
      containedInkWell: containedInkWell,
      rectCallback: rectCallback,
      borderRadius: borderRadius,
      customBorder: customBorder,
      radius: radius,
      onRemoved: onRemoved,
      textDirection: textDirection,
      keys: keys,
      keysDisabled: keysDisabled,
    );
  }
}

class _CustomInkSplash extends InkSplash {
  bool shouldPaint = true;

  final List<GlobalKey> keys;
  final List<bool> keysDisabled;

  _CustomInkSplash({
    required MaterialInkController super.controller,
    required super.referenceBox,
    required TextDirection super.textDirection,
    Offset? position,
    required Color super.color,
    bool super.containedInkWell = false,
    RectCallback? super.rectCallback,
    BorderRadius? super.borderRadius,
    ShapeBorder? super.customBorder,
    double? super.radius,
    super.onRemoved,
    required List<GlobalKey> this.keys,
    required List<bool> this.keysDisabled,
  }) : super(position: position) {
    assert(keys.length == keysDisabled.length);
    for (int i = 0; i < keys.length; i++) {
      if (!keysDisabled[i]) {
        continue;
      }
      //final box = keys[i].currentContext?.findRenderObject() as RenderBox?;
      final box =
          keys[i].currentContext?.findAncestorRenderObjectOfType<RenderStack>();
      if (box == null) {
        continue;
      }
      final boxGlobal = box.localToGlobal(Offset.zero);
      final tap = referenceBox.localToGlobal(position ?? Offset.zero);
      //box.constraints.maxHeight
      final hits = boxGlobal.dx < tap.dx &&
          boxGlobal.dx + box.size.height > tap.dx &&
          boxGlobal.dy < tap.dy &&
          boxGlobal.dy + box.size.width > tap.dy;
      if (hits) {
        shouldPaint = false;
        break;
      }
    }
  }

  @override
  void paintFeature(Canvas canvas, Matrix4 transform) {
    if (shouldPaint) {
      return super.paintFeature(canvas, transform);
    }
  }
}
