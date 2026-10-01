/*
 * Copyright 2026 InfAI (CC SES)
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */

import 'package:flutter/material.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/widgets/tabs/nav.dart';

import 'tab_config.dart';

/// One entry of the filter menu.
class _FilterOption {
  const _FilterOption({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;
}

/// Builds and appends the filter [PopupMenuButton] to [actions].
///
/// Hidden for [tabGroups], [tabSmartServices], and [tabDashboard].
class FilterMenuBuilder {
  FilterMenuBuilder({
    required this.navigationIndex,
    required this.currentFilter,
    required this.onChanged,
    required this.state,
    required this.onFilterApplied,
  });

  final int navigationIndex;

  /// Read on each use rather than captured when the app bar is built, so a
  /// filter replaced since then is not overwritten by a change made here.
  final DeviceSearchFilter Function() currentFilter;

  /// Receives the changed filter on every toggle; the owner stores it.
  final ValueChanged<DeviceSearchFilter> onChanged;
  final AppState state;

  /// Called after the user closes a filter dialog so the screen refreshes.
  final VoidCallback onFilterApplied;

  static const _hiddenTabs = {tabGroups, tabSmartServices, tabDashboard};

  bool get _isVisible => !_hiddenTabs.contains(navigationIndex);

  /// The Sensors tab loads its devices by id and never hides one, and
  /// Favorites never hides a favourite, so the toggle would do nothing there.
  bool get _showInactiveApplies =>
      navigationIndex != tabSensors &&
      !(tabConfigs[navigationIndex]?.ownsFavorites() ?? false);

  /// Appends the filter icon button to [actions] when appropriate.
  void appendTo(List<Widget> actions, BuildContext context) {
    if (!_isVisible) return;

    final count = _filterCount();

    actions.add(PopupMenuButton<VoidCallback>(
      tooltip: "Select Filters",
      icon: Badge(
        label: Text(count.toString()),
        isLabelVisible: count > 0,
        textColor: Colors.white,
        child: const Icon(Icons.filter_alt),
      ),
      onSelected: (onTap) => onTap(),
      // Built when the menu opens, not when the app bar does: the entries carry
      // the current filter state in their labels.
      itemBuilder: (_) => [
        for (final o in _buildOptions(context))
          PopupMenuItem<VoidCallback>(value: o.onTap, child: Text(o.label)),
        if (_filterCount() > 0) ...[
          const PopupMenuDivider(),
          PopupMenuItem<VoidCallback>(value: _reset, child: const Text('Reset')),
        ],
      ],
    ));
  }

  List<_FilterOption> _buildOptions(BuildContext context) {
    final config = tabConfigs[navigationIndex];
    final options = <_FilterOption>[];

    if (!(config?.ownsDeviceClass() ?? false) &&
        state.usedDeviceClasses.isNotEmpty) {
      options.add(_classesOption(context));
    }
    if (!(config?.ownsLocation() ?? false) && state.locations.isNotEmpty) {
      options.add(_locationsOption(context));
    }
    if (!(config?.ownsGroup() ?? false) && state.deviceGroups.isNotEmpty) {
      options.add(_groupsOption(context));
    }
    if (!(config?.ownsNetwork() ?? false) && state.networks.isNotEmpty) {
      options.add(_networksOption(context));
    }
    if (!(config?.ownsFavorites() ?? false)) {
      options.add(_favoritesToggleOption());
    }
    if (_showInactiveApplies) options.add(_showInactiveToggleOption());
    return options;
  }

  void _update(DeviceSearchFilter Function(DeviceSearchFilter) change) =>
      onChanged(change(currentFilter()));

  // ── Individual filter options ──────────────────────────────────────────────

  _FilterOption _classesOption(BuildContext context) => _FilterOption(
    label: '${currentFilter().deviceClassIds != null ? '✓ ' : ''}Classes',
    onTap: () {
      final classes = state.usedDeviceClasses;
      _showFilterDialog(
        context: context,
        title: 'Filter Classes',
        itemCount: classes.length,
        itemBuilder: (i) {
          final deviceClass = classes[i];
          return _FilterListTile(
            label: deviceClass.name,
            isSelected: currentFilter().deviceClassIds?.contains(deviceClass.id) ?? false,
            onChanged: (checked) => _update((f) =>
                checked ? f.withDeviceClass(deviceClass.id) : f.withoutDeviceClass(deviceClass.id)),
          );
        },
      );
    },
  );

  _FilterOption _locationsOption(BuildContext context) => _FilterOption(
    label: '${currentFilter().locationIds != null ? '✓ ' : ''}Locations',
    onTap: () => _showFilterDialog(
      context: context,
      title: 'Filter Locations',
      itemCount: state.locations.length,
      itemBuilder: (i) {
        final location = state.locations.elementAt(i);
        return _FilterListTile(
          label: location.name,
          isSelected: currentFilter().locationIds?.contains(location.id) ?? false,
          onChanged: (checked) => _update((f) =>
              checked ? f.withLocation(location.id) : f.withoutLocation(location.id)),
        );
      },
    ),
  );

  _FilterOption _groupsOption(BuildContext context) => _FilterOption(
    label: '${currentFilter().deviceGroupIds != null ? '✓ ' : ''}Groups',
    onTap: () => _showFilterDialog(
      context: context,
      title: 'Filter Groups',
      itemCount: state.deviceGroups.length,
      itemBuilder: (i) {
        final group = state.deviceGroups.elementAt(i);
        return _FilterListTile(
          label: group.name,
          isSelected: currentFilter().deviceGroupIds?.contains(group.id) ?? false,
          onChanged: (checked) => _update((f) =>
              checked ? f.withDeviceGroup(group.id) : f.withoutDeviceGroup(group.id)),
        );
      },
    ),
  );

  _FilterOption _networksOption(BuildContext context) => _FilterOption(
    label: '${currentFilter().networkIds != null ? '✓ ' : ''}Networks',
    onTap: () => _showFilterDialog(
      context: context,
      title: 'Filter Networks',
      itemCount: state.networks.length,
      itemBuilder: (i) {
        final network = state.networks.elementAt(i);
        return _FilterListTile(
          label: network.name,
          isSelected: currentFilter().networkIds?.contains(network.id) ?? false,
          onChanged: (checked) => _update((f) =>
              checked ? f.withNetwork(network.id) : f.withoutNetwork(network.id)),
        );
      },
    ),
  );

  _FilterOption _favoritesToggleOption() => _FilterOption(
    label: '${currentFilter().favorites == true ? '✓ ' : ''}Favorites',
    onTap: () {
      _update((f) => f.favorites == true
          ? f.without(favorites: true)
          : f.copyWith(favorites: true));
      onFilterApplied();
    },
  );

  _FilterOption _showInactiveToggleOption() => _FilterOption(
    label: '${currentFilter().showInactive ? '✓ ' : ''}Show inactive',
    onTap: () {
      _update((f) => f.copyWith(showInactive: !f.showInactive));
      onFilterApplied();
    },
  );

  void _reset() {
    final config = tabConfigs[navigationIndex];
    _update((f) {
      final cleared = f.without(
        locationIds: !(config?.ownsLocation() ?? false),
        deviceGroupIds: !(config?.ownsGroup() ?? false),
        networkIds: !(config?.ownsNetwork() ?? false),
        deviceClassIds: !(config?.ownsDeviceClass() ?? false),
        favorites: !(config?.ownsFavorites() ?? false),
      );
      return _showInactiveApplies ? cleared.copyWith(showInactive: false) : cleared;
    });
    onFilterApplied();
  }

  // ── Dialog helper ──────────────────────────────────────────────────────────

  void _showFilterDialog({
    required BuildContext context,
    required String title,
    required int itemCount,
    required Widget Function(int) itemBuilder,
  }) {
    showAdaptiveDialog(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          height: MediaQuery.of(context).size.height -
              MediaQuery.textScalerOf(context).scale(172),
          child: Material(
            color: const Color(0x00000000),
            child: ListView.builder(
              itemCount: itemCount,
              itemBuilder: (_, i) => itemBuilder(i),
            ),
          ),
        ),
        actions: [
          TextButton(
            child: const Text("OK"),
            onPressed: () {
              onFilterApplied();
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  // ── Filter count ───────────────────────────────────────────────────────────

  int _filterCount() {
    final config = tabConfigs[navigationIndex];
    final filter = currentFilter();
    var count = 0;
    if (!(config?.ownsLocation() ?? false)) {
      count += (filter.locationIds ?? []).length;
    }
    if (!(config?.ownsGroup() ?? false)) {
      count += (filter.deviceGroupIds ?? []).length;
    }
    if (!(config?.ownsNetwork() ?? false)) {
      count += (filter.networkIds ?? []).length;
    }
    if (!(config?.ownsDeviceClass() ?? false)) {
      count += (filter.deviceClassIds ?? []).length;
    }
    if (filter.favorites == true && !(config?.ownsFavorites() ?? false)) {
      count++;
    }
    if (filter.showInactive && _showInactiveApplies) count++;
    return count;
  }
}

// ── Private helper widget ────────────────────────────────────────────────────

/// A [ListTile] with a toggle switch that manages its own checked state via
/// [StatefulBuilder], calling [onChanged] with the new value.
class _FilterListTile extends StatefulWidget {
  const _FilterListTile({
    required this.label,
    required this.isSelected,
    required this.onChanged,
  });

  final String label;
  final bool isSelected;
  final void Function(bool checked) onChanged;

  @override
  State<_FilterListTile> createState() => _FilterListTileState();
}

class _FilterListTileState extends State<_FilterListTile> {
  late bool _checked;

  @override
  void initState() {
    super.initState();
    _checked = widget.isSelected;
  }

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(widget.label),
    trailing: Switch.adaptive(
      value: _checked,
      onChanged: (value) {
        setState(() => _checked = value);
        widget.onChanged(value);
      },
    ),
  );
}