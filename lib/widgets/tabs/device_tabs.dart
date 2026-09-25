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
        // A drill-down's own search override (e.g. classes/networks showing
        // search while hideSearch is otherwise true) doesn't survive it -
        // leaving any other way than its own back arrow stranded this at
        // whatever the drill-down last set it to.
        _hideSearchOverride = null;
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

  /// Handles a tap on one of the [navBarTabs] destinations. Re-tapping the
  /// tab that is already active leaves a drill-down instead of reloading -
  /// for Devices this covers every segment, since [barTabForView] maps all
  /// of them back to [tabDevices].
  void _onBarTap(int position, List<bool> disabled) {
    final tabIndex = navBarTabs[position];
    if (disabled[tabIndex]) {
      Toast.showToastNoContext("Currently unavailable");
      return;
    }
    if (barTabForView(_navigationIndex) == tabIndex) {
      onBackCallback?.call();
      return;
    }
    HapticFeedbackProxy.lightImpact();
    switchScreen(tabIndex, false);
  }

  /// Handles a tap on one of the Devices tab's [deviceSegmentTabs]. Re-tapping
  /// the active segment leaves a drill-down instead of reloading, the same
  /// way [_onBarTap] does for the bar itself.
  void _onSegmentTap(int segmentIndex, List<bool> disabled) {
    if (disabled[segmentIndex]) {
      Toast.showToastNoContext("Currently unavailable");
      return;
    }
    if (_navigationIndex == segmentIndex) {
      onBackCallback?.call();
      return;
    }
    HapticFeedbackProxy.lightImpact();
    switchScreen(segmentIndex, false);
  }

  Widget _buildNavigationBar(BuildContext context, List<bool> disabled) {
    final selected = navBarTabs.indexOf(barTabForView(_navigationIndex));
    final disabledColor = Theme.of(context).disabledColor;
    return NavigationBar(
      selectedIndex: selected < 0 ? 0 : selected,
      // enabled stays true even when disabled: NavigationDestination(enabled:
      // false) drops its onTap, which would also swallow the tap before
      // _onBarTap's own disabled check ever runs and can toast about it.
      destinations: navBarTabs.map((tabIndex) {
        final navItem = navItems.firstWhere((n) => n.index == tabIndex);
        return NavigationDestination(
          icon: Icon(navItem.icon,
              color: navItem.disabled ? disabledColor : null),
          label: navItem.name,
          tooltip: navItem.disabled ? "Currently unavailable" : null,
        );
      }).toList(),
      onDestinationSelected: (position) => _onBarTap(position, disabled),
    );
  }

  /// The Devices tab's secondary tab bar (All/Locations/Groups/Networks/
  /// Classes), shown under the app bar only while one of its segments is the
  /// active view.
  PreferredSizeWidget? _buildDeviceSegmentBar(
      BuildContext context, List<bool> disabled) {
    if (!deviceSegmentTabs.contains(_navigationIndex)) return null;
    return _DeviceSegmentBar(
      current: _navigationIndex,
      disabled: disabled,
      onSelected: (segmentIndex) => _onSegmentTap(segmentIndex, disabled),
    );
  }

  @override
  void initState() {
    super.initState();
    // Start on the page the user picked in the settings, ignoring a stored
    // index that no longer maps to a tab. A stored Locations/Groups/Networks/
    // Classes value opens Devices on that segment - they are still valid
    // navItem indices, so no extra mapping is needed here.
    final stored = Settings.getInitialTab();
    _navigationIndex =
        navItems.any((n) => n.index == stored) ? stored : tabFavorites;
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
    super.dispose();
  }

  /// A cheap signature of everything the app shell (app bar actions,
  /// navigation bar, segment bar) actually depends on: per-tab availability
  /// and the sizes of the filterable collections. Frequent device *state*
  /// updates (on/off, temperature, ...) don't change any of these, so the
  /// [Selector] in [build] skips the rebuild for them - this is what stops
  /// the shell from thrashing during the startup notify-storm.
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

  @override
  Widget build(BuildContext context) {
    return Selector<AppState, String>(
      selector: (_, state) => _shellSignature(state),
      builder: (context, _, __) {
        final state = AppState();
        // Kept in sync by _shellSignature above; also sets navItem.disabled,
        // which _buildNavigationBar and _buildDeviceSegmentBar read.
        final disabled = state.setAndGetDisabledTabs();
        final actions = _buildActions(context, state);
        final appBar = MyAppBar(customAppBarTitle ?? "");
        final leadingAction = onBackCallback != null
            ? IconButton(
          onPressed: () => onBackCallback!(),
          icon: const Icon(Icons.arrow_back),
        )
            : null;

        return PopScope(
          // canPop: false when there is a back callback so we can intercept.
          canPop: onBackCallback == null,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) onBackCallback?.call();
          },
          // highlightColor only, not a splashFactory: the M3 splash on the
          // nav bar and segment bar stays, this just drops the held-state
          // overlay Material shows underneath it everywhere in the shell.
          child: Theme(
            data: Theme.of(context).copyWith(highlightColor: Colors.transparent),
            child: Scaffold(
              floatingActionButton:
              showFab ? _buildFab(context) : null,
              appBar: appBar.getAppBar(context, actions, leadingAction,
                  _buildDeviceSegmentBar(context, disabled)),
              body: _buildTabBody(),
              bottomNavigationBar: _buildNavigationBar(context, disabled),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFab(BuildContext context) => FloatingActionButton(
    onPressed: () => _fabPressedController.add(null),
    backgroundColor: context.appColors.app,
    child: const Icon(Icons.add),
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
              Icon(Icons.error, color: context.appColors.error),
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
}

/// Secondary tab bar for the Devices tab's five segments. A plain [Row] of
/// hand-styled tabs, not Flutter's [TabBar]: a disabled segment still needs
/// its tap, to show the "unavailable" toast, without a [TabController]
/// animating to it first.
class _DeviceSegmentBar extends StatelessWidget implements PreferredSizeWidget {
  const _DeviceSegmentBar({
    required this.current,
    required this.disabled,
    required this.onSelected,
  });

  final int current;
  final List<bool> disabled;
  final void Function(int segmentIndex) onSelected;

  static const double _height = 48;

  @override
  Size get preferredSize => const Size.fromHeight(_height);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedColor = theme.colorScheme.primary;
    final unselectedColor = theme.colorScheme.onSurfaceVariant;
    final disabledColor = theme.disabledColor;

    // width: double.infinity: the AppBar's bottom slot only loosely
    // constrains its width, so without this the bar shrinks to its tabs'
    // content width instead of spanning the screen.
    return SizedBox(
      width: double.infinity,
      height: _height,
      child: Material(
        color: theme.navigationBarTheme.backgroundColor ?? theme.colorScheme.surface,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: deviceSegmentTabs
                .map((segmentIndex) => _segmentTab(
                    segmentIndex, selectedColor, unselectedColor, disabledColor))
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _segmentTab(int segmentIndex, Color selectedColor,
      Color unselectedColor, Color disabledColor) {
    // tabDevices is this segment bar's own "All" - the shared NavigationItem
    // name ("Devices") is already the main bar tab's label and would
    // otherwise show twice.
    final label = segmentIndex == tabDevices
        ? "All"
        : navItems.firstWhere((n) => n.index == segmentIndex).name;
    final isSelected = segmentIndex == current;
    final isDisabled = disabled[segmentIndex];
    final color = isDisabled
        ? disabledColor
        : (isSelected ? selectedColor : unselectedColor);

    return Tooltip(
      message: isDisabled ? "Currently unavailable" : label,
      child: InkWell(
        // Always wired, even when disabled: onSelected's own disabled check
        // is what shows the "unavailable" toast, so the tap has to reach it.
        onTap: () => onSelected(segmentIndex),
        child: Container(
          height: _height,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? selectedColor : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}