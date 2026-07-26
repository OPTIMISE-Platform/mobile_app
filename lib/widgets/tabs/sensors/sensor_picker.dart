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
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/models/sensor_pin.dart';
import 'package:mobile_app/services/devices.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/tabs/sensors/sensor_display.dart';

/// Lets the user pick a device and then one of its readable sensor values.
///
/// Returns the chosen value as a [SensorPin], or null if cancelled.
Future<SensorPin?> pickSensor(BuildContext context) =>
    Navigator.push<SensorPin>(
      context,
      platformPageRoute(
        context: context,
        builder: (_) => const _DevicePicker(),
      ),
    );

/// Device list with a search field. Searches the backend/cache directly instead
/// of reusing AppState's device list, which only holds the currently filtered
/// page of results.
class _DevicePicker extends StatefulWidget {
  const _DevicePicker();

  @override
  State<_DevicePicker> createState() => _DevicePickerState();
}

class _DevicePickerState extends State<_DevicePicker> {
  static const _limit = 50;

  final _searchController = TextEditingController();
  Timer? _debounce;
  List<DeviceInstance>? _devices;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(query));
  }

  Future<void> _search(String query) async {
    setState(() {
      _devices = null;
      _error = null;
    });
    try {
      await AppState().ensureInitialized();
      final result = await DevicesService.getDevices(
        _limit,
        0,
        DeviceSearchFilter(query),
        null,
      );
      if (!mounted) return;
      setState(() => _devices = result.devices);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not load devices');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PlatformScaffold(
      appBar: const PlatformAppBar(title: Text('Choose Device')),
      body: Column(
        children: [
          Padding(
            padding: MyTheme.inset,
            child: PlatformTextFormField(
              controller: _searchController,
              hintText: 'Search devices',
              onChanged: _onQueryChanged,
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) return Center(child: Text(_error!));
    final devices = _devices;
    if (devices == null) {
      return const Center(child: DelayedCircularProgressIndicator());
    }
    if (devices.isEmpty) {
      return const Center(child: Text('No devices found'));
    }
    return Scrollbar(
      child: ListView.separated(
        itemCount: devices.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (_, i) {
          final device = devices[i];
          return ListTile(
            title: Text(device.displayName),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final pin = await Navigator.push<SensorPin>(
                context,
                platformPageRoute(
                  context: context,
                  builder: (_) => _StatePicker(device),
                ),
              );
              if (pin != null && context.mounted) Navigator.pop(context, pin);
            },
          );
        },
      ),
    );
  }
}

/// Lists the readable (non-controlling) states of one device.
class _StatePicker extends StatelessWidget {
  final DeviceInstance device;

  const _StatePicker(this.device);

  @override
  Widget build(BuildContext context) {
    final deviceType = AppState().deviceTypes[device.device_type_id];
    if (deviceType != null) {
      device.prepareStates(deviceType);
    }
    final all = device.states;
    // Readable measurements first, then controls (switches and other inputs).
    final selectable = all.toList()
      ..sort((a, b) {
        if (a.isControlling != b.isControlling) {
          return a.isControlling ? 1 : -1;
        }
        return sensorTitle(a).compareTo(sensorTitle(b));
      });

    return PlatformScaffold(
      appBar: PlatformAppBar(title: Text(device.displayName)),
      body: selectable.isEmpty
          ? const Center(child: Text('This device has no values'))
          : Scrollbar(
              child: ListView.separated(
                itemCount: selectable.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (_, i) {
                  final DeviceState state = selectable[i];
                  final subtitle = sensorSubtitle(state, all, device);
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
