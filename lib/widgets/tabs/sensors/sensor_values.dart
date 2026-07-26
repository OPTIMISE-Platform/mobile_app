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

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
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
    with WidgetsBindingObserver {
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
    WidgetsBinding.instance.addObserver(this);
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
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed &&
        ModalRoute.of(context)?.isCurrent == true) {
      _loadValues();
    }
  }

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
        await AppState().loadDeviceGroups(context);
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

  /// The name shown above a card's value.
  String _ownerName(SensorPin pin) {
    if (pin.isGroup) {
      return _groups[pin.groupId]?.name ?? 'Unknown group';
    }
    return _devices[pin.deviceId]?.displayName ?? 'Unknown device';
  }

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
    final confirmed = await showPlatformDialog<bool>(
      context: context,
      builder: (_) => PlatformAlertDialog(
        title: const Text('Delete tab'),
        content: Text(
          tab.pins.isEmpty
              ? 'Delete "${tab.name}"?'
              : 'Delete "${tab.name}" and its ${tab.pins.length} value(s)?',
        ),
        actions: [
          PlatformDialogAction(
            child: PlatformText('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          PlatformDialogAction(
            child: PlatformText('Delete'),
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
    final action = await showPlatformModalSheet<String>(
      context: context,
      builder: (_) => PlatformWidget(
        material: (_, __) => SafeArea(
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
        cupertino: (_, __) => CupertinoActionSheet(
          actions: [
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, 'edit'),
              child: const Text('Rename / change icon'),
            ),
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, 'reorderValues'),
              child: const Text('Reorder values'),
            ),
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, 'reorderTabs'),
              child: const Text('Reorder tabs'),
            ),
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(context, 'delete'),
              child: const Text('Delete tab'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
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
      subtitle: _ownerName,
    );
    if (reordered == null || !mounted) return;
    await _updateCurrentPins(reordered);
  }

  // ---------------------------------------------------------------------------
  // Value actions
  // ---------------------------------------------------------------------------

  /// The FAB creates the first tab when there is none, otherwise adds a value.
  Future<void> _onFabPressed() async {
    if (_tabs.isEmpty) {
      await _addTab();
      return;
    }
    await _addSensor();
  }

  Future<void> _addSensor() async {
    if (_currentTab == null) return;
    final pin = await pickSensor(context);
    if (pin == null || !mounted) return;
    if (_pins.contains(pin)) {
      await showPlatformDialog(
        context: context,
        builder: (_) => PlatformAlertDialog(
          content: const Text('That value is already on this tab.'),
          actions: [
            PlatformDialogAction(
              child: PlatformText('OK'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      );
      return;
    }
    await _updateCurrentPins([..._pins, pin]);
    await _loadValues();
  }

  Future<void> _editPin(SensorPin pin) async {
    final state = _stateFor(pin);
    final result = await showNameIconDialog(
      context,
      title: 'Edit value',
      initialName: pin.alias ?? '',
      initialIconName: pin.iconName,
      nameHint: state != null ? sensorTitle(state) : 'Alias',
      nameRequired: false,
    );
    if (result == null || !mounted) return;
    final index = _pins.indexOf(pin);
    if (index < 0) return;
    final pins = [..._pins];
    pins[index] = pin.copyWith(
      alias: result.name, // empty clears
      iconName: result.iconName ?? '',
    );
    await _updateCurrentPins(pins);
  }

  Future<void> _removePin(SensorPin pin, String label) async {
    final confirmed = await showPlatformDialog<bool>(
      context: context,
      builder: (_) => PlatformAlertDialog(
        title: const Text('Remove value'),
        content: Text('Remove "$label" from this tab?'),
        actions: [
          PlatformDialogAction(
            child: PlatformText('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          PlatformDialogAction(
            child: PlatformText('Remove'),
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
    final action = await showPlatformModalSheet<String>(
      context: context,
      builder: (_) => PlatformWidget(
        material: (_, __) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Set alias / icon'),
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
        cupertino: (_, __) => CupertinoActionSheet(
          actions: [
            CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, 'edit'),
              child: const Text('Set alias / icon'),
            ),
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(context, 'remove'),
              child: const Text('Remove value'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
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
        const Divider(height: 1),
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
    if (_error != null && _devices.isEmpty) {
      return _buildFullHeightMessage(Text(_error!));
    }
    if (_loading && _devices.isEmpty) {
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
            PlatformElevatedButton(
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
                    'Add a sensor value with the + button to show it here.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  PlatformElevatedButton(
                    onPressed: _addSensor,
                    child: const Text('Add value'),
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

        return Card(
          child: InkWell(
            // The chart queries by device and service, which a group value has
            // neither of — the detail page disables it for groups too.
            onTap: state != null && state.value is num && device != null
                ? () => Navigator.push(
                    context,
                    platformPageRoute(
                      context: context,
                      builder: (_) => Chart(state),
                    ),
                  )
                : null,
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
                              _ownerName(pin),
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

  /// Whether the device offers a control for this value at all — either it is
  /// itself a control, or it is a measurement with a matching controlling state
  /// (the pairing the device detail page uses to make a reading tappable).
  ///
  /// Deliberately independent of the current value: [loadStates] nulls every
  /// value of an offline device, and the card still has to explain *why* it
  /// can't be controlled.
  bool _hasControls(DeviceState state, List<DeviceState> allStates) {
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
          s.serviceGroupKey == state.serviceGroupKey &&
          s.aspectId == state.aspectId,
    );
  }

  /// Whether the control can actually be triggered for the current value.
  bool _isControllable(DeviceState state, List<DeviceState> allStates) {
    if (!_hasControls(state, allStates)) return false;
    if (state.isControlling) return true;
    final config =
        functionConfigs[state.functionId] ??
        FunctionConfigDefault(state.functionId);
    return config.getRelatedControllingFunction(state.value) != null;
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
    if (states == null || !_hasControls(state, states)) {
      return _buildValueDisplay(state) ?? _placeholder;
    }

    if (device != null) {
      // Unreachable device: show why it can't be controlled, using the same
      // icons the device list uses. Checked before the value, which is null for
      // an offline device and would otherwise fall through to the placeholder.
      final connectionStatus = device.connection_state;
      final unavailable =
          connectionStatus == DeviceConnectionStatus.offline ||
          device.network?.localService == null && Settings.getLocalMode();
      if (unavailable) return _buildUnavailableValue(state, connectionStatus);
    }

    final display = _buildValueDisplay(state);
    if (display == null) return _placeholder;
    if (!_isControllable(state, states)) return display;

    return PlatformIconButton(
      cupertino: (_, __) => CupertinoIconButtonData(padding: EdgeInsets.zero),
      material: (_, __) => MaterialIconButtonData(splashRadius: 25),
      icon: display,
      onPressed: () => performDeviceStateAction(
        context: context,
        connectionStatus: device?.connection_state,
        element: state,
        states: states,
        isGroup: group != null,
        setState: setState,
        notifyEntity: device?.notifyStateChanged ?? group!.notifyStateChanged,
      ),
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
      offline ? PlatformIcons(context).error : Icons.lan_outlined,
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
