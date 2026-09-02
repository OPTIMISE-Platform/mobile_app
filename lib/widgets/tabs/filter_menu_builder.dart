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
    required this.filter,
    required this.state,
    required this.onFilterApplied,
  });

  final int navigationIndex;
  final DeviceSearchFilter filter;
  final AppState state;

  /// Called after the user closes a filter dialog so the screen refreshes.
  final VoidCallback onFilterApplied;

  static const _hiddenTabs = {tabGroups, tabSmartServices, tabDashboard};

  bool get _isVisible => !_hiddenTabs.contains(navigationIndex);

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
        state.deviceClasses.isNotEmpty) {
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
    return options;
  }

  // ── Individual filter options ──────────────────────────────────────────────

  _FilterOption _classesOption(BuildContext context) => _FilterOption(
    label: '${filter.deviceClassIds != null ? '✓ ' : ''}Classes',
    onTap: () => _showFilterDialog(
      context: context,
      title: 'Filter Classes',
      itemCount: state.deviceClasses.values.length,
      itemBuilder: (i) {
        final deviceClass = state.deviceClasses.values.elementAt(i);
        return _FilterListTile(
          label: deviceClass.name,
          isSelected: filter.deviceClassIds?.contains(deviceClass.id) ?? false,
          onChanged: (checked) {
            if (checked) {
              filter.addDeviceClass(deviceClass.id);
            } else {
              filter.removeDeviceClass(deviceClass.id);
            }
          },
        );
      },
    ),
  );

  _FilterOption _locationsOption(BuildContext context) => _FilterOption(
    label: '${filter.locationIds != null ? '✓ ' : ''}Locations',
    onTap: () => _showFilterDialog(
      context: context,
      title: 'Filter Locations',
      itemCount: state.locations.length,
      itemBuilder: (i) {
        final location = state.locations.elementAt(i);
        return _FilterListTile(
          label: location.name,
          isSelected: filter.locationIds?.contains(location.id) ?? false,
          onChanged: (checked) {
            if (checked) {
              filter.addLocation(location.id);
            } else {
              filter.removeLocation(location.id);
            }
          },
        );
      },
    ),
  );

  _FilterOption _groupsOption(BuildContext context) => _FilterOption(
    label: '${filter.deviceGroupIds != null ? '✓ ' : ''}Groups',
    onTap: () => _showFilterDialog(
      context: context,
      title: 'Filter Groups',
      itemCount: state.deviceGroups.length,
      itemBuilder: (i) {
        final group = state.deviceGroups.elementAt(i);
        return _FilterListTile(
          label: group.name,
          isSelected: filter.deviceGroupIds?.contains(group.id) ?? false,
          onChanged: (checked) {
            if (checked) {
              filter.addDeviceGroup(group.id);
            } else {
              filter.removeDeviceGroup(group.id);
            }
          },
        );
      },
    ),
  );

  _FilterOption _networksOption(BuildContext context) => _FilterOption(
    label: '${filter.networkIds != null ? '✓ ' : ''}Networks',
    onTap: () => _showFilterDialog(
      context: context,
      title: 'Filter Networks',
      itemCount: state.networks.length,
      itemBuilder: (i) {
        final network = state.networks.elementAt(i);
        return _FilterListTile(
          label: network.name,
          isSelected: filter.networkIds?.contains(network.id) ?? false,
          onChanged: (checked) {
            if (checked) {
              filter.addNetwork(network.id);
            } else {
              filter.removeNetwork(network.id);
            }
          },
        );
      },
    ),
  );

  _FilterOption _favoritesToggleOption() => _FilterOption(
    label: '${filter.favorites == true ? '✓ ' : ''}Favorites',
    onTap: () {
      filter.favorites = filter.favorites == true ? null : true;
      onFilterApplied();
    },
  );

  void _reset() {
    final config = tabConfigs[navigationIndex];
    if (!(config?.ownsLocation() ?? false)) filter.locationIds = null;
    if (!(config?.ownsGroup() ?? false)) filter.deviceGroupIds = null;
    if (!(config?.ownsNetwork() ?? false)) filter.networkIds = null;
    if (!(config?.ownsDeviceClass() ?? false)) filter.deviceClassIds = null;
    if (!(config?.ownsFavorites() ?? false)) filter.favorites = null;
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