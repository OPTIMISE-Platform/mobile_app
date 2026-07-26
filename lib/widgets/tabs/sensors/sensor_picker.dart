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

/// Lets the user pick a device or device group and then one of its values.
///
/// Returns the chosen value as a [SensorPin], or null if cancelled.
Future<SensorPin?> pickSensor(BuildContext context) =>
    Navigator.push<SensorPin>(
      context,
      platformPageRoute(
        context: context,
        builder: (_) => const _TargetPicker(),
      ),
    );

/// Device list (searchable, paged) and group list to choose from.
class _TargetPicker extends StatefulWidget {
  const _TargetPicker();

  @override
  State<_TargetPicker> createState() => _TargetPickerState();
}

class _TargetPickerState extends State<_TargetPicker> {
  static const _pageSize = 50;

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;

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
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
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
    return PlatformScaffold(
      appBar: const PlatformAppBar(title: Text('Choose Device or Group')),
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
              onSelectionChanged: (s) => setState(() => _showGroups = s.first),
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
    );
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
          return ListTile(
            title: Text(device.displayName),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openStatePicker(_DeviceTarget(device)),
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
          return ListTile(
            leading: const Icon(Icons.devices_other),
            title: Text(group.name),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openStatePicker(_GroupTarget(group)),
          );
        },
      ),
    );
  }

  Future<void> _openStatePicker(_PickTarget target) async {
    final pin = await Navigator.push<SensorPin>(
      context,
      platformPageRoute(context: context, builder: (_) => _StatePicker(target)),
    );
    if (pin != null && mounted) Navigator.pop(context, pin);
  }
}

/// What a [_StatePicker] lists values for — a device or a device group. Both
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

/// Lists the values of one device or group.
class _StatePicker extends StatelessWidget {
  final _PickTarget target;

  const _StatePicker(this.target);

  @override
  Widget build(BuildContext context) {
    final all = target.prepareStates();
    // Readable measurements first, then controls (switches and other inputs).
    final selectable = all.toList()
      ..sort((a, b) {
        if (a.isControlling != b.isControlling) {
          return a.isControlling ? 1 : -1;
        }
        return sensorTitle(a).compareTo(sensorTitle(b));
      });

    return PlatformScaffold(
      appBar: PlatformAppBar(title: Text(target.title)),
      body: selectable.isEmpty
          ? const Center(child: Text('No values available'))
          : Scrollbar(
              child: ListView.separated(
                itemCount: selectable.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (_, i) {
                  final DeviceState state = selectable[i];
                  final subtitle = sensorSubtitle(state, all, target.device);
                  final unit = sensorUnit(state);
                  return ListTile(
                    leading: state.isControlling
                        ? const Icon(Icons.input)
                        : const Icon(Icons.show_chart),
                    title: Text(sensorTitle(state)),
                    subtitle: subtitle.isEmpty ? null : Text(subtitle),
                    trailing: unit.isEmpty ? null : Text(unit),
                    onTap: () => Navigator.pop(context, SensorPin.of(state)),
                  );
                },
              ),
            ),
    );
  }
}
