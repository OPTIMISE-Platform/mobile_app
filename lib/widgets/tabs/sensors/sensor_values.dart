/*
 * Copyright 2026 InfAI (CC SES)
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
import 'package:mobile_app/mixins/resume_refresh_mixin.dart';

import 'package:flutter/material.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/config/functions/function_config.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/models/sensor_pin.dart';
import 'package:mobile_app/models/sensor_tab.dart';
import 'package:mobile_app/services/devices.dart';
import 'package:mobile_app/services/haptic_feedback_proxy.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/tabs/device_tabs.dart';
import 'package:mobile_app/widgets/tabs/sensors/name_icon_dialog.dart';
import 'package:mobile_app/widgets/tabs/sensors/reorder_page.dart';
import 'package:mobile_app/widgets/tabs/sensors/sensor_display.dart';
import 'package:mobile_app/widgets/tabs/sensors/sensor_icons.dart';
import 'package:mobile_app/widgets/tabs/sensors/sensor_picker.dart';
import 'package:mobile_app/widgets/tabs/sensors/sensor_sparkline.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/chart.dart';
import 'package:mobile_app/widgets/tabs/shared/device_state_action.dart';

/// A page of user-defined tabs, each showing a freely composed set of
/// individual sensor values as cards.
///
/// The configuration lives in [Settings] (see `getSensorTabs`), so it is a user
/// preference that survives cache clears. Pinned devices are fetched by id
/// rather than read from `AppState().devices`, which only holds the currently
/// filtered page of devices.
class SensorValues extends StatefulWidget {
  const SensorValues({super.key});

  @override
  State<SensorValues> createState() => _SensorValuesState();
}

class _SensorValuesState extends State<SensorValues>
    with ResumeRefreshMixin {
  StreamSubscription? _fabSubscription;
  StreamSubscription? _refreshSubscription;
  DeviceTabsState? parentState;

  List<SensorTab> _tabs = [];
  int _selected = 0;

  /// Devices of the selected tab by id, carrying the prepared states whose
  /// values we show.
  final Map<String, DeviceInstance> _devices = {};

  /// Device groups of the selected tab by id, for pins that target a group.
  final Map<String, DeviceGroup> _groups = {};
  bool _loading = false;
  String? _error;

  /// Last two hours of history per pin, drawn behind the card. Loaded after the
  /// values so a slow history never delays the readings.
  final Map<SensorPin, SparkSeries> _sparklines = {};

  SensorTab? get _currentTab =>
      _selected >= 0 && _selected < _tabs.length ? _tabs[_selected] : null;

  List<SensorPin> get _pins => _currentTab?.pins ?? const [];

  @override
  void initState() {
    super.initState();
    _tabs = Settings.getSensorTabs();
    parentState =
        context.findAncestorStateOfType<State<DeviceTabs>>()
            as DeviceTabsState?;
    _fabSubscription = parentState?.fabPressed.listen((_) => _onFabPressed());
    _refreshSubscription = AppState().refreshPressed.listen(
      (_) => _loadValues(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadValues();
    });
  }

  @override
  void dispose() {
    _fabSubscription?.cancel();
    _refreshSubscription?.cancel();
    super.dispose();
  }

  @override
  void onResumed() => _loadValues();

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  /// Loads the values of the selected tab only — switching tabs reloads.
  Future<void> _loadValues() async {
    final pins = _pins;
    if (pins.isEmpty) {
      setState(() {
        _devices.clear();
        _groups.clear();
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AppState().ensureInitialized();

      // Groups are already held by AppState (the tab shell loads them), while
      // pinned devices have to be fetched by id.
      final groupIds = pins.map((p) => p.groupId).whereType<String>().toSet();
      if (groupIds.isNotEmpty && AppState().deviceGroups.isEmpty) {
        // The tab shell normally loads them, but this page can be the start
        // page and run before that finishes.
        await AppState().loadDeviceGroups();
      }
      final groups = AppState().deviceGroups
          .where((g) => groupIds.contains(g.id))
          .toList();
      for (final group in groups) {
        group.prepareStates();
      }

      final deviceIds = pins
          .map((p) => p.deviceId)
          .whereType<String>()
          .toSet()
          .toList();
      var devices = <DeviceInstance>[];
      if (deviceIds.isNotEmpty) {
        final filter = DeviceSearchFilter('')..deviceIds = deviceIds;
        final result = await DevicesService.getDevices(
          deviceIds.length,
          0,
          filter,
          null,
        );
        devices = result.devices;
        for (final device in devices) {
          final deviceType = AppState().deviceTypes[device.device_type_id];
          if (deviceType != null) device.prepareStates(deviceType);
        }
      }

      // Only request the functions actually pinned, not every state.
      final functionIds = pins.map((p) => p.functionId).toSet().toList();
      await AppState().loadStates(devices, groups, functionIds);
      if (!mounted) return;
      setState(() {
        _devices
          ..clear()
          ..addEntries(devices.map((d) => MapEntry(d.id, d)));
        _groups
          ..clear()
          ..addEntries(groups.map((g) => MapEntry(g.id, g)));
        _loading = false;
      });
      unawaited(_loadSparklines(pins));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load sensor values';
        _loading = false;
      });
    }
  }

  /// Fetches each pin's 2h history in the background, showing every sparkline
  /// as soon as it arrives rather than waiting for all of them.
  Future<void> _loadSparklines(List<SensorPin> pins) async {
    await Future.wait(
      pins.map((pin) async {
        final state = _stateFor(pin);
        if (state == null || !canShowSparkline(state)) return;
        final values = await loadSparklineValues(state);
        if (values == null || !mounted) return;
        // The tab may have been switched while this was in flight.
        if (!_pins.contains(pin)) return;
        setState(() => _sparklines[pin] = values);
      }),
    );
  }

  /// The live state a pin refers to, or null while it hasn't loaded (or the
  /// device/group/value no longer exists).
  DeviceState? _stateFor(SensorPin pin) {
    final states = pin.isGroup
        ? _groups[pin.groupId]?.states
        : _devices[pin.deviceId]?.states;
    if (states == null) return null;
    for (final state in states) {
      if (pin.matches(state)) return state;
    }
    return null;
  }

  /// The device or group a pin belongs to, the card's subtitle by default.
  String _ownerName(SensorPin pin) {
    if (pin.isGroup) {
      return _groups[pin.groupId]?.name ?? 'Unknown group';
    }
    return _devices[pin.deviceId]?.displayName ?? 'Unknown device';
  }

  /// The card's small top line: what the user typed, or the owner's name.
  String _subtitleOf(SensorPin pin) => pin.subtitle ?? _ownerName(pin);

  /// What a card listens to for value changes.
  Listenable _notifierFor(SensorPin pin) =>
      (pin.isGroup
          ? _groups[pin.groupId]?.stateNotifier
          : _devices[pin.deviceId]?.stateNotifier) ??
      _neverNotifies;

  // ---------------------------------------------------------------------------
  // Persistence helpers
  // ---------------------------------------------------------------------------

  Future<void> _saveTabs(List<SensorTab> tabs, {int? select}) async {
    await Settings.setSensorTabs(tabs);
    if (!mounted) return;
    setState(() {
      _tabs = tabs;
      if (select != null) _selected = select;
      if (_selected >= _tabs.length) _selected = _tabs.length - 1;
      if (_selected < 0) _selected = 0;
    });
  }

  /// Replaces the selected tab's pins.
  Future<void> _updateCurrentPins(List<SensorPin> pins) async {
    final current = _currentTab;
    if (current == null) return;
    final tabs = [..._tabs];
    tabs[_selected] = current.copyWith(pins: pins);
    await _saveTabs(tabs);
  }

  // ---------------------------------------------------------------------------
  // Tab actions
  // ---------------------------------------------------------------------------

  Future<void> _addTab() async {
    final result = await showNameIconDialog(
      context,
      title: 'New tab',
      nameHint: 'Tab name',
      confirmLabel: 'Create',
    );
    if (result == null || !mounted) return;
    final tabs = [
      ..._tabs,
      SensorTab.create(name: result.name, iconName: result.iconName),
    ];
    await _saveTabs(tabs, select: tabs.length - 1);
    await _loadValues();
  }

  Future<void> _editTab(int index) async {
    final tab = _tabs[index];
    final result = await showNameIconDialog(
      context,
      title: 'Edit tab',
      initialName: tab.name,
      initialIconName: tab.iconName,
      nameHint: 'Tab name',
    );
    if (result == null || !mounted) return;
    final tabs = [..._tabs];
    tabs[index] = tab.copyWith(
      name: result.name,
      iconName: result.iconName ?? '', // empty clears
    );
    await _saveTabs(tabs);
  }

  Future<void> _deleteTab(int index) async {
    final tab = _tabs[index];
    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (_) => AlertDialog.adaptive(
        title: const Text('Delete tab'),
        content: Text(
          tab.pins.isEmpty
              ? 'Delete "${tab.name}"?'
              : 'Delete "${tab.name}" and its ${tab.pins.length} value(s)?',
        ),
        actions: [
          TextButton(
            child: Text('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          TextButton(
            child: Text('Delete'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final tabs = [..._tabs]..removeAt(index);
    await _saveTabs(tabs, select: index > 0 ? index - 1 : 0);
    await _loadValues();
  }

  Future<void> _showTabMenu(int index) async {
    HapticFeedbackProxy.lightImpact();
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename / change icon'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.swap_vert),
              title: const Text('Reorder values'),
              onTap: () => Navigator.pop(context, 'reorderValues'),
            ),
            ListTile(
              leading: const Icon(Icons.reorder),
              title: const Text('Reorder tabs'),
              onTap: () => Navigator.pop(context, 'reorderTabs'),
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('Delete tab'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == 'edit') await _editTab(index);
    if (action == 'reorderValues') await _reorderValues();
    if (action == 'reorderTabs') await _reorderTabs();
    if (action == 'delete') await _deleteTab(index);
  }

  Future<void> _reorderTabs() async {
    final reordered = await reorderItems<SensorTab>(
      context,
      title: 'Reorder tabs',
      items: _tabs,
      label: (t) => t.name,
      icon: (t) => sensorIcon(t.iconName),
      subtitle: (t) => '${t.pins.length} value(s)',
    );
    if (reordered == null || !mounted) return;
    // Keep showing the same tab after the move.
    final currentId = _currentTab?.id;
    final newIndex = currentId == null
        ? 0
        : reordered
              .indexWhere((t) => t.id == currentId)
              .clamp(0, reordered.length - 1);
    await _saveTabs(reordered, select: newIndex);
  }

  Future<void> _reorderValues() async {
    final current = _currentTab;
    if (current == null) return;
    final reordered = await reorderItems<SensorPin>(
      context,
      title: 'Reorder values',
      items: current.pins,
      label: (p) {
        final state = _stateFor(p);
        return p.alias ?? (state != null ? sensorTitle(state) : 'Unavailable');
      },
      icon: (p) => sensorIcon(p.iconName),
      // The card's own subtitle even when hidden there — this list needs
      // something to tell two values of one device apart.
      subtitle: _subtitleOf,
    );
    if (reordered == null || !mounted) return;
    await _updateCurrentPins(reordered);
  }

  // ---------------------------------------------------------------------------
  // Value actions
  // ---------------------------------------------------------------------------

  /// The FAB creates the first tab when there is none, otherwise adds values.
  Future<void> _onFabPressed() async {
    if (_tabs.isEmpty) {
      await _addTab();
      return;
    }
    await _addSensors();
  }

  /// Adds every value the user checked in one trip through the picker.
  Future<void> _addSensors() async {
    if (_currentTab == null) return;
    // The picker shows the values already here as taken, so nothing it returns
    // should be a duplicate — filtered anyway, since a duplicate would make two
    // cards that can't be told apart.
    final picked = await pickSensors(context, existing: _pins);
    if (picked == null || !mounted) return;
    final added = picked.where((p) => !_pins.contains(p)).toList();
    if (added.isEmpty) return;
    await _updateCurrentPins([..._pins, ...added]);
    await _loadValues();
  }

  Future<void> _editPin(SensorPin pin) async {
    final state = _stateFor(pin);
    final result = await showNameIconDialog(
      context,
      title: 'Edit value',
      initialName: pin.alias ?? '',
      initialIconName: pin.iconName,
      // Both fields fall back to what the card would show on its own, so the
      // hints double as a preview of leaving them empty.
      nameHint: state != null ? sensorTitle(state) : 'Title',
      nameRequired: false,
      withSubtitle: true,
      initialSubtitle: pin.subtitle ?? '',
      subtitleHint: _ownerName(pin),
      initialSubtitleHidden: pin.hideSubtitle,
    );
    if (result == null || !mounted) return;
    final index = _pins.indexOf(pin);
    if (index < 0) return;
    final pins = [..._pins];
    pins[index] = pin.copyWith(
      alias: result.name, // empty clears
      iconName: result.iconName ?? '',
      subtitle: result.subtitle, // empty falls back to the device/group name
      hideSubtitle: result.subtitleHidden,
    );
    await _updateCurrentPins(pins);
  }

  Future<void> _removePin(SensorPin pin, String label) async {
    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (_) => AlertDialog.adaptive(
        title: const Text('Remove value'),
        content: Text('Remove "$label" from this tab?'),
        actions: [
          TextButton(
            child: Text('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          TextButton(
            child: Text('Remove'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _updateCurrentPins(_pins.where((p) => p != pin).toList());
  }

  Future<void> _showPinMenu(SensorPin pin, String label) async {
    HapticFeedbackProxy.lightImpact();
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Edit title / subtitle / icon'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('Remove value'),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (action == 'edit') await _editPin(pin);
    if (action == 'remove') await _removePin(pin, label);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_tabs.isEmpty) return _buildNoTabsState();

    return Column(
      children: [
        _buildTabStrip(),
        // Reloads keep the current values on screen (on resume, for instance),
        // so without this the page would refresh with no sign of it. Same
        // height as the divider it replaces, to avoid shifting the grid.
        // When nothing is loaded yet the body shows a full spinner instead.
        if (_loading && (_devices.isNotEmpty || _groups.isNotEmpty))
          const _RefreshingBar()
        else
          const Divider(height: 2),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              HapticFeedbackProxy.lightImpact();
              await _loadValues();
            },
            child: Scrollbar(child: _buildTabBody()),
          ),
        ),
      ],
    );
  }

  Widget _buildTabStrip() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            for (var i = 0; i < _tabs.length; i++) _buildTabChip(i),
            IconButton(
              tooltip: 'New tab',
              icon: const Icon(Icons.add),
              onPressed: _addTab,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabChip(int index) {
    final tab = _tabs[index];
    final selected = index == _selected;
    final icon = sensorIcon(tab.iconName);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          if (selected) return;
          setState(() => _selected = index);
          _loadValues();
        },
        onLongPress: () => _showTabMenu(index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? MyTheme.appColor : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? MyTheme.appColor
                  : Theme.of(context).dividerColor,
            ),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 18,
                  color: selected ? MyTheme.textColor : null,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                tab.name,
                style: TextStyle(
                  color: selected ? MyTheme.textColor : null,
                  fontWeight: selected ? FontWeight.bold : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabBody() {
    if (_pins.isEmpty) return _buildEmptyTabState();
    // A tab holding only group values never fills _devices, so both checks have
    // to look at either kind — otherwise such a tab would keep showing the
    // full-page spinner while the refresh bar was already up, and would swallow
    // load errors.
    final loadedAnything = _devices.isNotEmpty || _groups.isNotEmpty;
    if (_error != null && !loadedAnything) {
      return _buildFullHeightMessage(Text(_error!));
    }
    if (_loading && !loadedAnything) {
      return _buildFullHeightMessage(const DelayedCircularProgressIndicator());
    }
    return GridView.builder(
      padding: MyTheme.inset,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.05,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _pins.length,
      itemBuilder: (_, i) => _buildCard(_pins[i]),
    );
  }

  Widget _buildNoTabsState() {
    return Center(
      child: Padding(
        padding: MyTheme.inset,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'No tabs yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Create a tab to group the sensor values you want to see.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _addTab,
              child: const Text('Create tab'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyTabState() {
    return LayoutBuilder(
      builder: (context, constraint) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraint.maxHeight),
          child: Center(
            child: Padding(
              padding: MyTheme.inset,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'No values yet',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Add sensor values with the + button to show them here.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _addSensors,
                    child: const Text('Add values'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFullHeightMessage(Widget child) {
    return LayoutBuilder(
      builder: (context, constraint) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraint.maxHeight),
          child: Center(child: child),
        ),
      ),
    );
  }

  Widget _buildCard(SensorPin pin) {
    final device = pin.isGroup ? null : _devices[pin.deviceId];
    final group = pin.isGroup ? _groups[pin.groupId] : null;
    final state = _stateFor(pin);

    // Rebuild just this card when its device's or group's values change, so
    // values that arrive progressively show up without rebuilding the grid.
    return ListenableBuilder(
      listenable: _notifierFor(pin),
      builder: (context, _) {
        final title =
            pin.alias ?? (state != null ? sensorTitle(state) : 'Unavailable');
        final icon = sensorIcon(pin.iconName);

        // The chart queries by device and service, which a group value has
        // neither of — the detail page disables it for groups too.
        final openChart = state != null && state.value is num && device != null
            ? () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => Chart(state),
                ),
              )
            : null;

        return Card(
          child: InkWell(
            // Without a chart the card had no tap action of its own, so a tap
            // that missed the small value button rippled the whole card and did
            // nothing — which is every switch, and every group value. Let the
            // card trigger the action in that case.
            onTap: openChart ?? _actionFor(state, device, group),
            onLongPress: () => _showPinMenu(pin, title),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_sparklines[pin] != null)
                  Sparkline(_sparklines[pin]!, color: MyTheme.appColor),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!pin.hideSubtitle) ...[
                        Row(
                          children: [
                            if (pin.isGroup) ...[
                              Icon(
                                Icons.devices_other,
                                size: 12,
                                color: Theme.of(
                                  context,
                                ).textTheme.bodySmall?.color,
                              ),
                              const SizedBox(width: 3),
                            ],
                            Expanded(
                              child: Text(
                                _subtitleOf(pin),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(
                                    context,
                                  ).textTheme.bodySmall?.color,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                      ],
                      Row(
                        children: [
                          if (icon != null) ...[
                            Icon(icon, size: 18),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Align(
                        alignment: Alignment.centerRight,
                        child: _buildValue(state, device, group),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Whether a control for this value exists at all — either it is itself a
  /// control, or it is a measurement with a matching controlling state (the
  /// pairing the device detail page uses to make a reading tappable).
  ///
  /// Deliberately independent of the current value: [loadStates] nulls every
  /// value of an offline device, and the card still has to explain *why* it
  /// can't be controlled.
  bool _hasControls(
    DeviceState state,
    List<DeviceState> allStates,
    bool isGroup,
  ) {
    if (state.isControlling) return true;
    final config =
        functionConfigs[state.functionId] ??
        FunctionConfigDefault(state.functionId);
    final controllingFunctions = config.getAllRelatedControllingFunctions();
    if (controllingFunctions == null || controllingFunctions.isEmpty) {
      return false;
    }
    return allStates.any(
      (s) =>
          s.isControlling &&
          controllingFunctions.contains(s.functionId) &&
          (isGroup || _pairsWithinDevice(s, state)),
    );
  }

  /// A device's measurement and its control belong together when they sit in the
  /// same service group and describe the same aspect.
  ///
  /// A group's criteria share neither: they pair by device class, and a
  /// controlling criterion typically carries no aspect at all, so requiring this
  /// would leave every group value unswitchable.
  bool _pairsWithinDevice(DeviceState control, DeviceState measurement) =>
      control.serviceGroupKey == measurement.serviceGroupKey &&
      control.aspectId == measurement.aspectId;

  /// Whether the control can actually be triggered for the current value.
  bool _isControllable(
    DeviceState state,
    List<DeviceState> allStates,
    bool isGroup,
  ) {
    if (!_hasControls(state, allStates, isGroup)) return false;
    if (state.isControlling) return true;
    final config =
        functionConfigs[state.functionId] ??
        FunctionConfigDefault(state.functionId);
    return config.getRelatedControllingFunction(state.value) != null;
  }

  /// The controlling state a group's measured value switches to, or null when it
  /// can't be determined.
  ///
  /// Needed because [performDeviceStateAction] resolves a measurement's control
  /// by aspect, which no group criterion satisfies. Handing it the control
  /// directly puts it on its `isControlling` branch and skips that lookup.
  DeviceState? _groupControlFor(
    DeviceState state,
    List<DeviceState> allStates,
  ) {
    final config =
        functionConfigs[state.functionId] ??
        FunctionConfigDefault(state.functionId);
    final target = config.getRelatedControllingFunction(state.value);
    if (target == null) return null;
    final candidates = allStates
        .where((s) => s.isControlling && s.functionId == target)
        .toList(growable: false);
    // More than one means the group spans device classes that each bring their
    // own control; there is no single command to send, so leave it alone rather
    // than switch an arbitrary subset.
    if (candidates.length != 1) return null;
    return candidates.first;
  }

  /// Whether the device can't be reached right now — the same two cases the
  /// device list distinguishes.
  bool _isUnavailable(DeviceInstance device) =>
      device.connection_state == DeviceConnectionStatus.offline ||
      device.network?.localService == null && Settings.getLocalMode();

  /// What triggering this value does, or null when there is nothing to trigger.
  ///
  /// Shared by the value button and the card itself, so both stay in step.
  VoidCallback? _actionFor(
    DeviceState? state,
    DeviceInstance? device,
    DeviceGroup? group,
  ) {
    if (state == null || state.transitioning) return null;
    final states = device?.states ?? group?.states;
    if (states == null) return null;
    if (device != null && _isUnavailable(device)) return null;

    // Act on the control itself. A device's measurement is handed over as it is,
    // because the shared action pairs it up the same way the detail page does; a
    // group's measurement has to be resolved here (see [_groupControlFor]).
    final DeviceState element;
    if (group != null && !state.isControlling) {
      final control = _groupControlFor(state, states);
      if (control == null) return null;
      element = control;
    } else {
      if (!_isControllable(state, states, group != null)) return null;
      element = state;
    }
    if (element.transitioning) return null;

    return () => performDeviceStateAction(
      context: context,
      connectionStatus: device?.connection_state,
      element: element,
      states: states,
      isGroup: group != null,
      setState: setState,
      notifyEntity: device?.notifyStateChanged ?? group!.notifyStateChanged,
    );
  }

  static const _placeholder = Text('—', style: TextStyle(fontSize: 24));

  Widget _buildValue(
    DeviceState? state,
    DeviceInstance? device,
    DeviceGroup? group,
  ) {
    if (state == null) return _placeholder;
    if (state.transitioning) return const DelayedCircularProgressIndicator();

    // A group has no connection state of its own, so it never shows the
    // unavailability icons — its members' reachability isn't known here.
    final states = device?.states ?? group?.states;
    if (states == null || !_hasControls(state, states, group != null)) {
      return _buildValueDisplay(state) ?? _placeholder;
    }

    // Unreachable device: show why it can't be controlled, using the same icons
    // the device list uses. Checked before the value, which is null for an
    // offline device and would otherwise fall through to the placeholder.
    if (device != null && _isUnavailable(device)) {
      return _buildUnavailableValue(state, device.connection_state);
    }

    final display = _buildValueDisplay(state);
    if (display == null) return _placeholder;
    final action = _actionFor(state, device, group);
    if (action == null) return display;

    return IconButton(
      splashRadius: 25,
      icon: display,
      onPressed: action,
    );
  }

  /// The device list's unavailability icons, keeping the last reading visible
  /// when there is one.
  Widget _buildUnavailableValue(
    DeviceState state,
    DeviceConnectionStatus? connectionStatus,
  ) {
    final offline = connectionStatus == DeviceConnectionStatus.offline;
    final warning = Icon(
      offline ? Icons.error : Icons.lan_outlined,
      color: MyTheme.warnColor,
    );
    if (state.isControlling || state.value == null) return warning;
    final display = _buildValueDisplay(state);
    if (display == null) return warning;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        warning,
        const SizedBox(width: 4),
        Flexible(child: display),
      ],
    );
  }

  /// The value itself, or null when there is nothing to show yet.
  Widget? _buildValueDisplay(DeviceState state) {
    // Some functions render as an icon/custom widget (e.g. on/off) rather than
    // a bare number — prefer that, as the detail page does.
    final custom = functionConfigs[state.functionId]?.displayValue(
      state.value,
      context,
    );
    if (custom != null) return custom;

    // A control without its own reading has nothing to display but its action.
    if (state.isControlling) return const Icon(Icons.input);

    if (state.value == null) {
      return _loading ? const DelayedCircularProgressIndicator() : null;
    }

    final unit = sensorUnit(state);
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Text(
        '${formatValue(state.value)}${unit.isEmpty ? '' : ' $unit'}',
        maxLines: 1,
        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// Placeholder listenable for cards whose device hasn't loaded yet.
final ChangeNotifier _neverNotifies = ChangeNotifier();

/// A slim progress bar signalling a refresh that keeps the current values on
/// screen.
///
/// Appears only once loading has lasted long enough to be worth showing, so a
/// reload served from the cache doesn't flash it. Occupies its height either
/// way, so nothing below it moves.
class _RefreshingBar extends StatefulWidget {
  const _RefreshingBar();

  @override
  State<_RefreshingBar> createState() => _RefreshingBarState();
}

class _RefreshingBarState extends State<_RefreshingBar> {
  static const _height = 2.0;

  bool _show = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _show
      ? const LinearProgressIndicator(minHeight: _height)
      : const SizedBox(height: _height);
}
