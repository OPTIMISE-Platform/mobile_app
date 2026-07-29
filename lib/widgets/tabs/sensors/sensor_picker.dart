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

import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/models/sensor_pin.dart';
import 'package:mobile_app/services/devices.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/tabs/sensors/sensor_display.dart';

/// Lets the user pick devices or device groups and check off as many of their
/// values as wanted.
///
/// The selection is kept while browsing from device to device, so composing a
/// tab takes one trip through the picker instead of one per value. Returns the
/// checked values as [SensorPin]s, or null if cancelled.
///
/// [existing] are the values already on the page; they show up checked and
/// can't be picked again.
Future<List<SensorPin>?> pickSensors(
  BuildContext context, {
  Iterable<SensorPin> existing = const [],
}) => Navigator.push<List<SensorPin>>(
  context,
  platformPageRoute(
    context: context,
    builder: (_) => _TargetPicker(existing: existing.toSet()),
  ),
);

/// The values checked so far, shared by the target list and the value lists so
/// the selection survives navigating between devices and groups.
class _Selection extends ChangeNotifier {
  /// Values already on the page — checked, but not part of the result.
  final Set<SensorPin> _existing;

  /// Insertion-ordered, so values arrive on the page in the order they were
  /// checked.
  final Set<SensorPin> _picked = {};

  _Selection(this._existing);

  int get count => _picked.length;

  List<SensorPin> get picked => _picked.toList();

  bool isPicked(SensorPin pin) => _picked.contains(pin);

  /// Whether this value is already on the page, making it unpickable.
  bool isExisting(SensorPin pin) => _existing.contains(pin);

  void toggle(SensorPin pin) {
    if (!_picked.remove(pin)) _picked.add(pin);
    notifyListeners();
  }

  int countForDevice(String deviceId) =>
      _picked.where((p) => p.deviceId == deviceId).length;

  int countForGroup(String groupId) =>
      _picked.where((p) => p.groupId == groupId).length;
}

/// Device list (searchable, paged) and group list to choose from.
class _TargetPicker extends StatefulWidget {
  final Set<SensorPin> existing;

  const _TargetPicker({required this.existing});

  @override
  State<_TargetPicker> createState() => _TargetPickerState();
}

class _TargetPickerState extends State<_TargetPicker> {
  static const _pageSize = 50;

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;

  late final _Selection _selection = _Selection(widget.existing);

  bool _showGroups = false;

  final List<DeviceInstance> _devices = [];
  String _query = '';
  bool _initialLoadDone = false;
  bool _loadingPage = false;
  bool _allLoaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Keeps the per-target counts and the Done button in step with what was
    // checked on the value pages.
    _selection.addListener(_onSelectionChanged);
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _selection.removeListener(_onSelectionChanged);
    _selection.dispose();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 400) {
      _loadNextPage();
    }
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _query = query;
      _reload();
    });
  }

  Future<void> _reload() async {
    setState(() {
      _devices.clear();
      _initialLoadDone = false;
      _allLoaded = false;
      _error = null;
    });
    await _loadNextPage();
  }

  /// Loads the next page of devices.
  ///
  /// The list is paged rather than capped: a single 50-device request left
  /// everything beyond it unreachable by scrolling, even though searching found
  /// it.
  Future<void> _loadNextPage() async {
    if (_loadingPage || _allLoaded) return;
    _loadingPage = true;
    try {
      await AppState().ensureInitialized();
      final result = await DevicesService.getDevices(
        _pageSize,
        _devices.length,
        DeviceSearchFilter(_query),
        _devices.isEmpty ? null : _devices.last,
      );
      if (!mounted) return;
      setState(() {
        _devices.addAll(result.devices);
        _allLoaded = result.devices.length < _pageSize;
        _initialLoadDone = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load devices';
        _initialLoadDone = true;
      });
    } finally {
      _loadingPage = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Going back would throw the selection away, which is a lot to lose after
      // checking off a dozen values.
      canPop: _selection.count == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: PlatformScaffold(
        appBar: PlatformAppBar(
          title: const Text('Choose Device or Group'),
          trailingActions: [
            _buildDoneAction(
              context,
              _selection,
              () => Navigator.pop(context, _selection.picked),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: MyTheme.inset,
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Devices')),
                  ButtonSegment(value: true, label: Text('Groups')),
                ],
                selected: {_showGroups},
                onSelectionChanged: (s) =>
                    setState(() => _showGroups = s.first),
              ),
            ),
            if (!_showGroups)
              Padding(
                padding: MyTheme.inset,
                child: PlatformTextFormField(
                  controller: _searchController,
                  hintText: 'Search devices',
                  onChanged: _onQueryChanged,
                ),
              ),
            Expanded(child: _showGroups ? _buildGroups() : _buildDevices()),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDiscard() async {
    final discard = await showPlatformDialog<bool>(
      context: context,
      builder: (_) => PlatformAlertDialog(
        title: const Text('Discard selection'),
        content: Text('Discard the ${_selection.count} value(s) you selected?'),
        actions: [
          PlatformDialogAction(
            child: PlatformText('Keep choosing'),
            onPressed: () => Navigator.pop(context, false),
          ),
          PlatformDialogAction(
            child: PlatformText('Discard'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.pop(context);
  }

  Widget _buildDevices() {
    if (_error != null && _devices.isEmpty) {
      return Center(child: Text(_error!));
    }
    if (!_initialLoadDone) {
      return const Center(child: DelayedCircularProgressIndicator());
    }
    if (_devices.isEmpty) {
      return const Center(child: Text('No devices found'));
    }
    return Scrollbar(
      controller: _scrollController,
      child: ListView.separated(
        controller: _scrollController,
        // One extra row carries the "loading more" indicator.
        itemCount: _devices.length + (_allLoaded ? 0 : 1),
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (_, i) {
          if (i >= _devices.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: DelayedCircularProgressIndicator()),
            );
          }
          final device = _devices[i];
          final picked = _selection.countForDevice(device.id);
          return ListTile(
            title: Text(device.displayName),
            subtitle: picked == 0 ? null : Text('$picked selected'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openValuePicker(_DeviceTarget(device)),
          );
        },
      ),
    );
  }

  Widget _buildGroups() {
    final groups = AppState().deviceGroups;
    if (groups.isEmpty) {
      return const Center(child: Text('No device groups'));
    }
    return Scrollbar(
      child: ListView.separated(
        itemCount: groups.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (_, i) {
          final group = groups[i];
          final picked = _selection.countForGroup(group.id);
          return ListTile(
            leading: const Icon(Icons.devices_other),
            title: Text(group.name),
            subtitle: picked == 0 ? null : Text('$picked selected'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openValuePicker(_GroupTarget(group)),
          );
        },
      ),
    );
  }

  /// Opens one target's values. Coming back keeps whatever was checked there;
  /// only its Done button ends the whole picker.
  Future<void> _openValuePicker(_PickTarget target) async {
    final done = await Navigator.push<bool>(
      context,
      platformPageRoute(
        context: context,
        builder: (_) => _ValuePicker(target, _selection),
      ),
    );
    if (done == true && mounted) Navigator.pop(context, _selection.picked);
  }
}

/// Confirms the selection, showing how much has piled up so far.
///
/// A plain text action was lost in the app bar, so this is a filled pill in a
/// colour the bar doesn't use — the way out of the picker has to be obvious
/// while the user is busy ticking values off.
Widget _buildDoneAction(
  BuildContext context,
  _Selection selection,
  VoidCallback onDone,
) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    child: FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: dark ? MyTheme.appColor : Colors.white,
        foregroundColor: Colors.black,
        disabledBackgroundColor: dark ? Colors.white24 : Colors.black12,
        disabledForegroundColor: dark ? Colors.white54 : Colors.black45,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
      onPressed: selection.count == 0 ? null : onDone,
      child: Text(selection.count == 0 ? 'Done' : 'Done (${selection.count})'),
    ),
  );
}

/// What a [_ValuePicker] lists values for — a device or a device group. Both
/// expose prepared [DeviceState]s, but build them differently.
abstract class _PickTarget {
  String get title;

  List<DeviceState> prepareStates();

  /// Only a device can disambiguate a value by service group.
  DeviceInstance? get device;
}

class _DeviceTarget implements _PickTarget {
  final DeviceInstance _device;

  _DeviceTarget(this._device);

  @override
  String get title => _device.displayName;

  @override
  DeviceInstance? get device => _device;

  @override
  List<DeviceState> prepareStates() {
    final deviceType = AppState().deviceTypes[_device.device_type_id];
    if (deviceType != null) _device.prepareStates(deviceType);
    return _device.states;
  }
}

class _GroupTarget implements _PickTarget {
  final DeviceGroup _group;

  _GroupTarget(this._group);

  @override
  String get title => _group.name;

  @override
  DeviceInstance? get device => null;

  @override
  List<DeviceState> prepareStates() {
    _group.prepareStates();
    return _group.states;
  }
}

/// Lists the values of one device or group, each one checkable.
///
/// Tapping a value only ticks it off — the page stays open so the rest of the
/// device's values can be picked in the same visit. Pops `true` when the user
/// is done choosing altogether, and nothing when they just go back to the
/// target list.
class _ValuePicker extends StatefulWidget {
  final _PickTarget target;
  final _Selection selection;

  const _ValuePicker(this.target, this.selection);

  @override
  State<_ValuePicker> createState() => _ValuePickerState();
}

class _ValuePickerState extends State<_ValuePicker> {
  late final List<DeviceState> _all = widget.target.prepareStates();

  /// Readable measurements first, then controls (switches and other inputs).
  late final List<DeviceState> _selectable = _all.toList()
    ..sort((a, b) {
      if (a.isControlling != b.isControlling) {
        return a.isControlling ? 1 : -1;
      }
      return sensorTitle(a).compareTo(sensorTitle(b));
    });

  @override
  Widget build(BuildContext context) {
    return PlatformScaffold(
      appBar: PlatformAppBar(
        title: Text(widget.target.title),
        trailingActions: [
          _buildDoneAction(
            context,
            widget.selection,
            () => Navigator.pop(context, true),
          ),
        ],
      ),
      body: _selectable.isEmpty
          ? const Center(child: Text('No values available'))
          : Scrollbar(
              child: ListView.separated(
                itemCount: _selectable.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (_, i) => _buildTile(_selectable[i]),
              ),
            ),
    );
  }

  Widget _buildTile(DeviceState state) {
    final pin = SensorPin.of(state);
    final existing = widget.selection.isExisting(pin);
    final picked = existing || widget.selection.isPicked(pin);

    var subtitle = sensorSubtitle(state, _all, widget.target.device);
    if (existing) {
      subtitle = subtitle.isEmpty
          ? 'Already added'
          : '$subtitle · Already added';
    }
    final unit = sensorUnit(state);

    return ListTile(
      leading: state.isControlling
          ? const Icon(Icons.input)
          : const Icon(Icons.show_chart),
      title: Text(sensorTitle(state)),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (unit.isNotEmpty) ...[Text(unit), const SizedBox(width: 8)],
          Icon(
            picked ? Icons.check_box : Icons.check_box_outline_blank,
            // A value already on the page stays ticked but greyed out, so it
            // reads as "there already" rather than "just picked".
            color: existing
                ? Theme.of(context).disabledColor
                : (picked ? MyTheme.appColor : null),
          ),
        ],
      ),
      enabled: !existing,
      onTap: () => setState(() => widget.selection.toggle(pin)),
    );
  }
}
