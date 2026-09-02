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
import 'package:flutter/rendering.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/services/haptic_feedback_proxy.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/tabs/dashboard/dashboard.dart';
import 'package:mobile_app/widgets/tabs/devices/device_list.dart';
import 'package:mobile_app/widgets/tabs/nav.dart';
import 'package:mobile_app/widgets/tabs/sensors/sensor_values.dart';
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

class DeviceTabsState extends State<DeviceTabs> {
  Timer? _searchDebounce;
  /// Position within the bottom bar's items — not a tab index. The bar's first
  /// entry is the configurable start page, so the two no longer coincide.
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

  final _sidebarController =
  SidebarXController(selectedIndex: 0, extended: true);

  // Indexed by tab index, so it has to cover every registered nav item.
  final _tabKeys = List.generate(navItems.length, (_) => GlobalKey());

  // Cached drawer: rebuilding SidebarX on every AppState notify is what makes
  // opening the drawer janky. The drawer only depends on the per-tab disabled
  // flags and the theme brightness, so we memoize it on exactly those inputs.
  Widget? _cachedDrawer;
  String? _cachedDrawerKey;

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

    // The sensors tab loads the devices it needs by id itself.
    if (!isInitialLoad &&
        index != tabDashboard &&
        index != tabSmartServices &&
        index != tabSensors) {
      // defer search on initial load — data isn't ready yet anyway

      // searchDevices() skips an unchanged filter. On a fresh start that filter
      // still equals the initial empty one for every tab without an owned
      // filter, so without forcing, the very first load would never happen and
      // the device list would stay empty.
      final force = !AppState().devicesLoadedOnce;
      if (config.ownsFavorites()) {
        filter.favorites = true;
        AppState().searchDevices(filter, force);
        filter.favorites = false;
      } else {
        AppState().searchDevices(filter, force);
      }
    }
  }

  void _reloadCurrentTab() => _applyTabConfig(_navigationIndex);

  /// Entries of the bottom bar: the page the user picked as their start page,
  /// followed by Dashboard (or Favorites, when the start page *is* Dashboard).
  List<NavigationItem> get _bottomBarNavItems {
    NavigationItem itemFor(int index) =>
        navItems.firstWhere((n) => n.index == index, orElse: () => navItems.first);

    final first = itemFor(Settings.getInitialTab());
    final second =
        itemFor(first.index == tabDashboard ? tabFavorites : tabDashboard);
    return first.index == second.index ? [first] : [first, second];
  }

  Widget _buildBottomNavBar(BuildContext context, List<bool> disabled) {
    final disabledColor = Theme.of(context).disabledColor;

    final barNavItems = _bottomBarNavItems;
    final items = barNavItems
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

    // Highlight the current tab when it is in the bar, otherwise keep the last
    // bar selection (the drawer can navigate to tabs the bar doesn't show).
    final currentInBar =
        barNavItems.indexWhere((n) => n.index == _navigationIndex);

    return BottomNavigationBar(
      items: items,
      currentIndex: currentInBar >= 0
          ? currentInBar
          : _bottomBarIndex.clamp(0, items.length - 1),
      // The callback reports the position in the bar, which is not the tab
      // index — the start page can be any tab.
      onTap: (position) {
        final navItem = barNavItems[position];
        if (disabled[navItem.index]) return;
        setState(() {
          _bottomBarIndex = position;
          _navigationIndex = navItem.index;
          _sidebarController.selectIndex(navItem.index);
        });
        HapticFeedbackProxy.lightImpact();
        switchScreen(navItem.index, false);
      },
    );
  }

  @override
  void initState() {
    super.initState();
    // Start on the page the user picked in the settings, ignoring a stored
    // index that no longer maps to a tab.
    final stored = Settings.getInitialTab();
    _navigationIndex =
        navItems.any((n) => n.index == stored) ? stored : tabFavorites;
    _sidebarController.selectIndex(_navigationIndex);
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
          state.loadDeviceGroups(),
          state.loadNetworks(context)
        ]).then((_) {
          if (!mounted) return;
          switchScreen(_navigationIndex, true);
        });
      });
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _fabPressedController.close();
    _sidebarController.dispose();
    super.dispose();
  }

  /// A cheap signature of everything the app shell (app bar actions, drawer,
  /// bottom nav, splash factory) actually depends on: per-tab availability and
  /// the sizes of the filterable collections. Frequent device *state* updates
  /// (on/off, temperature, ...) don't change any of these, so the [Selector]
  /// in [build] skips the rebuild for them — this is what stops the shell from
  /// thrashing during the startup notify-storm and while the drawer animates.
  String _shellSignature(AppState state) {
    final disabled = state.setAndGetDisabledTabs();
    final sb = StringBuffer();
    for (final d in disabled) {
      sb.write(d ? '1' : '0');
    }
    sb
      ..write('|')
      ..write(state.deviceClasses.length)
      ..write(',')
      ..write(state.locations.length)
      ..write(',')
      ..write(state.deviceGroups.length)
      ..write(',')
      ..write(state.networks.length);
    // Shell-local state has to be part of the signature too: Selector returns
    // its cached subtree whenever the signature is unchanged, so a setState()
    // on this State alone would not reach the shell. Leaving showFab out is why
    // switching to a tab with a FAB showed none until some unrelated AppState
    // change happened to alter the signature.
    sb
      ..write('|')
      ..write(_navigationIndex)
      ..write(showFab ? '1' : '0')
      ..write(_hideSearch ? '1' : '0')
      ..write(onBackCallback == null ? '0' : '1')
      ..write(',')
      ..write(customAppBarTitle ?? '');
    return sb.toString();
  }

  /// Returns the drawer, rebuilding [_buildSidebar] only when the disabled
  /// flags or the theme brightness change. Keeps the SidebarX subtree stable
  /// across the many rebuilds triggered by tab switches, search and filtering.
  Widget _getSidebar(BuildContext context) {
    final key = StringBuffer();
    for (final n in navItems) {
      key.write(n.disabled ? '1' : '0');
    }
    key.write(MyTheme.isDarkMode ? 'D' : 'L');
    final k = key.toString();
    if (_cachedDrawer == null || _cachedDrawerKey != k) {
      _cachedDrawerKey = k;
      _cachedDrawer = _buildSidebar(context);
    }
    return _cachedDrawer!;
  }

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, String>(
      selector: (_, state) => _shellSignature(state),
      builder: (context, _, __) {
        final state = AppState();
        // Kept in sync by _shellSignature above; also sets navItem.disabled,
        // which _getSidebar reads.
        final disabled = state.setAndGetDisabledTabs();
        final actions = _buildActions(context, state);
        final appBar = MyAppBar(customAppBarTitle ?? "");
        final leadingAction = onBackCallback != null
            ? IconButton(
          onPressed: () => onBackCallback!(),
          icon: const Icon(Icons.arrow_back),
        )
            : null;

        final drawer = _getSidebar(context);

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
                  keysDisabled: disabled,
                ),
                highlightColor: Colors.transparent,
              ),
              child: Scaffold(
                drawer: drawer,
                appBar: appBar.getAppBar(context, actions, leadingAction),
                body: _buildTabBody(),
                bottomNavigationBar: _buildBottomNavBar(context, disabled),
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
      actions.add(IconButton(
        icon: const Icon(Icons.search),
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
      case tabSensors:
        return const SensorValues();
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