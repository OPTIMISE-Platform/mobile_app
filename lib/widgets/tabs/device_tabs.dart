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
import 'package:flutter/rendering.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/services/haptic_feedback_proxy.dart';
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
import '../shared/toast.dart';
import 'filter_menu_builder.dart';
import 'tab_config.dart';

class DeviceTabs extends StatefulWidget {
  const DeviceTabs({super.key});

  @override
  State<DeviceTabs> createState() => DeviceTabsState();
}

class DeviceTabsState extends State<DeviceTabs> with RestorationMixin {
  Timer? _searchDebounce;
  int _bottomBarIndex = 0;
  int _navigationIndex = 0;
  bool _initialized = false;
  bool _searchClosed = false;
  bool? _hideSearchOverride;

  final DeviceSearchFilter filter = DeviceSearchFilter.empty();

  Function? onBackCallback;
  String? customAppBarTitle;

  bool showFab = false;
  final StreamController _fabPressedController = StreamController();
  late final Stream _fabPressedStream =
  _fabPressedController.stream.asBroadcastStream();

  Stream get fabPressed => _fabPressedStream;

  final _cupertinoSearchController = RestorableTextEditingController();
  final controller = CupertinoTabController(initialIndex: 0);
  final _sidebarController =
  SidebarXController(selectedIndex: 0, extended: true);

  final _tabKeys = List.generate(8, (_) => GlobalKey());

  TabConfig get _currentConfig =>
      tabConfigs[_navigationIndex] ??
          TabConfig(
            index: _navigationIndex,
            hideSearch: true,
            showFabResolver: () => false,
          );

  bool get _hideSearch => _hideSearchOverride ?? _currentConfig.hideSearch;

  void setHideSearchOverride(bool? value) => setState(() => _hideSearchOverride = value);

  void _searchChanged(String search) {
    if (filter.query == search) return;
    if (search.isNotEmpty && _searchClosed) return;
    filter.query = search;
    if (_searchDebounce?.isActive ?? false) _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 300),
          () => _reloadCurrentTab(),
    );
  }

  void switchScreen(int selectedIndex, bool force) {
    if (_navigationIndex == selectedIndex && !force) return;
    setState(() {
      if (_navigationIndex != selectedIndex) {
        customAppBarTitle = null;
        onBackCallback = null;
        // Clear the filter owned by the tab we're leaving.
        tabConfigs[_navigationIndex]?.clearOwnedFilter(filter);
        _navigationIndex = selectedIndex;
      }
      _applyTabConfig(selectedIndex);
    });
  }

  /// Apply the tab's config and trigger a device search when needed.
  void _applyTabConfig(int index, {bool isInitialLoad = false}) {
    final config = tabConfigs[index];
    if (config == null) return;

    showFab = config.showFab;

    if (!isInitialLoad && index != tabDashboard && index != tabSmartServices) {
      // defer search on initial load — data isn't ready yet anyway
      if (config.ownsFavorites()) {
        filter.favorites = true;
        AppState().searchDevices(filter, context);
        filter.favorites = false;
      } else {
        AppState().searchDevices(filter, context);
      }
    }
  }

  void _reloadCurrentTab() => _applyTabConfig(_navigationIndex);

  PlatformNavBar _buildBottomNavBar(BuildContext context) {
    final disabled = AppState().setAndGetDisabledTabs();

    final disabledColor = isCupertino(context)
        ? Theme.of(context).disabledColor.withAlpha(32)
        : Theme.of(context).disabledColor;

    final items = navItems
        .where((item) => ['Favorites', 'Dashboard'].contains(item.name))
        .map((navItem) => BottomNavigationBarItem(
      tooltip: navItem.disabled ? "Currently unavailable" : null,
      icon: Icon(
        navItem.icon,
        key: _tabKeys[navItem.index],
        color: navItem.disabled ? disabledColor : null,
      ),
      label: navItem.name,
    ))
        .toList();

    return PlatformNavBar(
      items: items,
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true; // set first to prevent re-entry
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final state = Provider.of<AppState>(context, listen: false);
        // parallel — don't await sequentially
        Future.wait([
          state.loadDeviceGroups(context),
          state.loadNetworks(context),
          state.loadLocations(context),
          state.loadDevices(context), // move here from initState
        ]).then((_) {
          if (!mounted) return;
          switchScreen(_bottomBarIndex, true);
        });
      });
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
        final actions = _buildActions(context, state);
        final appBar = MyAppBar(customAppBarTitle ?? "");
        final leadingAction = onBackCallback != null
            ? IconButton(
          onPressed: () => onBackCallback!(),
          icon: Icon(PlatformIcons(context).back),
        )
            : null;

        final drawer = _buildSidebar(context);

        return PopScope(
          // canPop: false when there is a back callback so we can intercept.
          canPop: onBackCallback == null,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) onBackCallback?.call();
          },
          child: Scaffold(
            floatingActionButton:
            showFab ? _buildFab() : null,
            body: Theme(
              data: Theme.of(context).copyWith(
                splashFactory: _CustomInkSplashFactory(
                  keys: _tabKeys,
                  keysDisabled: AppState().setAndGetDisabledTabs(),
                ),
                highlightColor: Colors.transparent,
              ),
              child: PlatformScaffold(
                material: (_, __) => MaterialScaffoldData(drawer: drawer),
                appBar: appBar.getAppBar(context, actions, leadingAction),
                body: Column(
                  children: [
                    _buildCupertinoSearch(context),
                    Expanded(child: _buildTabBody()),
                  ],
                ),
                cupertino: (context, _) =>
                    CupertinoPageScaffoldData(controller: controller),
                bottomNavBar: _buildBottomNavBar(context),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFab() => Container(
    margin: const EdgeInsets.only(bottom: 55),
    child: FloatingActionButton(
      onPressed: () => _fabPressedController.add(null),
      backgroundColor: MyTheme.appColor,
      child: Icon(Icons.add, color: MyTheme.textColor),
    ),
  );

  List<Widget> _buildActions(BuildContext context, AppState state) {
    final actions = <Widget>[];

    if (!_hideSearch) {
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
                _searchChanged,
              ),
            );
            _searchClosed = true;
            _searchDebounce?.cancel();
            _searchChanged("");
          },
        ),
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

    if (Settings.getFilterMode()) {
      FilterMenuBuilder(
        navigationIndex: _navigationIndex,
        filter: filter,
        state: state,
        onFilterApplied: () => setState(_reloadCurrentTab),
      ).appendTo(actions, context);
    }

    actions.addAll(MyAppBar.getDefaultActions(context));
    return actions;
  }

  Widget _buildCupertinoSearch(BuildContext context) {
    if (_hideSearch) return const SizedBox.shrink();
    return PlatformWidget(
      cupertino: (_, __) => Container(
        padding: MyTheme.inset,
        child: CupertinoSearchTextField(
          onChanged: _searchChanged,
          style: TextStyle(color: MyTheme.textColor),
          itemColor:
          MyTheme.textColor ?? CupertinoColors.secondaryLabel,
          restorationId: "cupertino-device-search",
          controller: _cupertinoSearchController.value,
        ),
      ),
      material: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildTabBody() {
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
      default:
        return Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, color: MyTheme.errorColor),
              SizedBox(
                width: MediaQuery.textScalerOf(context).scale(1) * 12,
                height: 0,
              ),
              const Text("not implemented"),
            ],
          ),
        );
    }
  }

  Widget _buildSidebar(BuildContext context) {
    final sidebarItems = navItems.map((navItem) {
      if (navItem.disabled) {
        return SidebarXItem(
          icon: Icons.disabled_by_default,
          label: navItem.name,
          selectable: false,
          onTap: () {
            Navigator.pop(context);
            Toast.showToastNoContext("Currently unavailable");
          },
        );
      }
      return SidebarXItem(
        icon: navItem.icon,
        label: navItem.name,
        selectable: true,
        onTap: () {
          setState(() {
            _sidebarController.selectIndex(navItem.index);
            _navigationIndex = navItem.index;
          });
          switchScreen(_navigationIndex, true);
          Navigator.pop(context);
        },
      );
    }).toList();

    final isDark = MyTheme.isDarkMode;
    final textColor = MyTheme.textColor;
    final selectorColor = isDark ? MyTheme.appColor : Colors.teal.shade50;
    final iconColor = isDark ? Colors.white : MyTheme.appColor;
    final backgroundColor =
    isDark ? const Color(0xFF424242) : Colors.white;
    final divider =
    Divider(color: textColor?.withOpacity(0.3), height: 1);

    return SidebarX(
      controller: _sidebarController,
      extendedTheme: const SidebarXTheme(
        width: 200,
        margin: EdgeInsets.only(right: 10),
      ),
      items: sidebarItems,
      headerDivider: divider,
      footerDivider: divider,
      headerBuilder: (context, extended) => SafeArea(
        child: SizedBox(
          height: 100,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Image.asset('assets/icon/icon.png'),
          ),
        ),
      ),
      theme: SidebarXTheme(
        decoration: BoxDecoration(color: backgroundColor),
        textStyle: TextStyle(color: textColor),
        selectedTextStyle: TextStyle(color: textColor),
        itemTextPadding: const EdgeInsets.only(left: 30),
        selectedItemTextPadding: const EdgeInsets.only(left: 30),
        selectedItemDecoration: BoxDecoration(
          color: selectorColor,
          borderRadius: BorderRadius.circular(10),
        ),
        selectedIconTheme: IconThemeData(color: iconColor),
        iconTheme: IconThemeData(color: iconColor, size: 20),
      ),
    );
  }

  @override
  String? get restorationId => "device_list";

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(
        _cupertinoSearchController, "_cupertinoSearchController");
  }
}

class _CustomInkSplashFactory extends InteractiveInkFeatureFactory {
  _CustomInkSplashFactory({
    required this.keys,
    required this.keysDisabled,
  });

  final List<GlobalKey> keys;
  final List<bool> keysDisabled;

  @override
  InteractiveInkFeature create({
    required MaterialInkController controller,
    required RenderBox referenceBox,
    required Offset position,
    required Color color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    ShapeBorder? customBorder,
    double? radius,
    VoidCallback? onRemoved,
  }) {
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
  _CustomInkSplash({
    required super.controller,
    required super.referenceBox,
    required super.textDirection,
    Offset? position,
    required super.color,
    super.containedInkWell = false,
    super.rectCallback,
    super.borderRadius,
    super.customBorder,
    super.radius,
    super.onRemoved,
    required this.keys,
    required this.keysDisabled,
  }) : super(position: position) {
    assert(keys.length == keysDisabled.length);
    _shouldPaint = !_hitsAnyDisabledTab(position ?? Offset.zero);
  }

  final List<GlobalKey> keys;
  final List<bool> keysDisabled;
  late final bool _shouldPaint;

  bool _hitsAnyDisabledTab(Offset position) {
    final tapGlobal = referenceBox.localToGlobal(position);
    for (var i = 0; i < keys.length; i++) {
      if (!keysDisabled[i]) continue;
      final box =
      keys[i].currentContext?.findAncestorRenderObjectOfType<RenderStack>();
      if (box == null) continue;
      final origin = box.localToGlobal(Offset.zero);
      // Note: width/height used on their correct axes.
      if (tapGlobal.dx >= origin.dx &&
          tapGlobal.dx <= origin.dx + box.size.width &&
          tapGlobal.dy >= origin.dy &&
          tapGlobal.dy <= origin.dy + box.size.height) {
        return true;
      }
    }
    return false;
  }

  @override
  void paintFeature(Canvas canvas, Matrix4 transform) {
    if (_shouldPaint) super.paintFeature(canvas, transform);
  }
}