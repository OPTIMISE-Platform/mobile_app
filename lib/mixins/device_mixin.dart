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

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/exceptions/api_unavailable_exception.dart';
import 'package:mobile_app/models/device_class.dart';
import 'package:mobile_app/models/device_command_response.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/services/device_classes.dart';
import 'package:mobile_app/services/device_commands.dart';
import 'package:mobile_app/services/device_groups.dart';
import 'package:mobile_app/services/device_types.dart';
import 'package:mobile_app/services/devices.dart';
import 'package:mobile_app/services/mgw_device_manager.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/widgets/shared/toast.dart';
import 'package:mutex/mutex.dart';

mixin DeviceMixin on ChangeNotifier {
  static final _logger = Logger(printer: SimplePrinter());

  final Map<String, DeviceClass> deviceClasses = {};
  final _deviceClassesMutex = Mutex();

  final Map<String, DeviceType> deviceTypes = {};
  final _deviceTypesMutex = Mutex();

  final List<DeviceInstance> devices = [];
  final _devicesMutex = Mutex();
  bool _allDevicesLoaded = false;
  bool _devicesLoadedOnce = false;
  int _deviceOffset = 0;

  final List<DeviceGroup> deviceGroups = [];
  final _deviceGroupsMutex = Mutex();
  bool _deviceGroupsLoadedOnce = false;

  DeviceSearchFilter _deviceSearchFilter = DeviceSearchFilter.empty();

  int totalDevices = 0;
  final _totalDevicesMutex = Mutex();

  bool get loadingDevices => _totalDevicesMutex.isLocked || _devicesMutex.isLocked;
  bool get allDevicesLoaded => _allDevicesLoaded;

  /// True once an initial device load has completed. Callers that rely on the
  /// device list being populated must force their search until then, since
  /// [searchDevices] skips an unchanged filter — which on a fresh start matches
  /// the initial empty filter.
  bool get devicesLoadedOnce => _devicesLoadedOnce;

  /// True once devices *and* device groups have each completed an initial load.
  /// Before that, "no favorites yet" is indistinguishable from "not loaded
  /// yet" — the favorites screen uses this to show a spinner instead of briefly
  /// flashing the empty "Add Favorites" state during startup.
  bool get favoritesDataLoaded => _devicesLoadedOnce && _deviceGroupsLoadedOnce;
  bool get loadingDeviceClasses => _deviceClassesMutex.isLocked;
  bool loadingDeviceGroups() => _deviceGroupsMutex.isLocked;

  /// Implemented by [AppState] — called before loading devices to ensure
  /// device classes, types, and other metadata are loaded first.
  Future<void> ensureInitialized();

  // ---------------------------------------------------------------------------
  // Device classes
  // ---------------------------------------------------------------------------

  Future<bool> loadDeviceClasses() async {
    final locked = _deviceClassesMutex.isLocked;
    await _deviceClassesMutex.acquire();
    if (locked) {
      // Deduplicated onto the load that was already running; releasing here is
      // what lets that dedup happen more than once per process.
      _deviceClassesMutex.release();
      return true;
    }
    try {
      final fetched = await DeviceClassesService.getDeviceClasses();
      // Swap after the fetch: clearing first would leave the map visibly
      // empty for the whole request, clearing at all is what drops entries
      // deleted on the backend.
      deviceClasses.clear();
      for (final e in fetched) {
        deviceClasses[e.id] = e;
      }
    } catch (e) {
      final err = 'Could not get device classes: $e';
      _logger.e(err);
      Toast.showToastNoContext(err);
      return false;
    } finally {
      _deviceClassesMutex.release();
    }
    notifyListeners();
    return true;
  }

  // ---------------------------------------------------------------------------
  // Device types
  // ---------------------------------------------------------------------------

  Future<bool> loadDeviceTypes() async {
    final locked = _deviceTypesMutex.isLocked;
    await _deviceTypesMutex.acquire();
    if (locked) {
      _deviceTypesMutex.release();
      return true;
    }
    try {
      final fetched = await DeviceTypesService.getDeviceTypes();
      deviceTypes.clear();
      for (final e in fetched) {
        deviceTypes[e.id] = e;
      }
    } catch (e) {
      final err = 'Could not get device types: $e';
      _logger.e(err);
      Toast.showToastNoContext(err);
      return false;
    } finally {
      _deviceTypesMutex.release();
    }
    notifyListeners();
    return true;
  }

  // ---------------------------------------------------------------------------
  // Devices
  // ---------------------------------------------------------------------------

  Future<void> searchDevices(
      DeviceSearchFilter filter,
      BuildContext context, [
        bool force = false,
      ]) async {
    if (!force && _deviceSearchFilter == filter) return;
    _allDevicesLoaded = false;
    notifyListeners();
    _deviceSearchFilter = filter.clone();
    _deviceOffset = 0;
    await loadDevices(context, null, true);
  }

  Future<void> refreshDevices(BuildContext context) =>
      searchDevices(_deviceSearchFilter, context, true);

  Future<void> loadDevices(
      BuildContext context, [
        int? offset,
        bool clear = false,
      ]) async {
    debugPrint("loadDevices");
    if (_allDevicesLoaded) return;

    final locked = _devicesMutex.isLocked;
    await _devicesMutex.acquire();
    if (locked) {
      _devicesMutex.release();
      return;
    }

    if (_allDevicesLoaded || (offset != null && offset < devices.length)) {
      _devicesMutex.release();
      notifyListeners();
      return;
    }
    if (clear) devices.clear();

    await ensureInitialized();

    const limit = 50;
    late final List<DeviceInstance> newDevices;
    try {
      final d = await DevicesService.getDevices(
        limit,
        _deviceOffset,
        _deviceSearchFilter,
        devices.isNotEmpty ? devices.last : null,
      );
      newDevices = d.devices;
      totalDevices = d.total;
    } catch (e) {
      _logger.e('Could not get devices: $e');
      Toast.showToastNoContext('Could not load devices');
      notifyListeners();
      _devicesMutex.release();
      return;
    }

    _devicesLoadedOnce = true;
    _allDevicesLoaded = newDevices.length < limit;
    _deviceOffset += newDevices.length;

    if (newDevices.isNotEmpty) {
      for (final d in newDevices) {
        if (deviceTypes[d.device_type_id] != null) {
          d.prepareStates(deviceTypes[d.device_type_id]!);
        }
      }
      devices.addAll(newDevices);
      notifyListeners(); // <-- show devices immediately, before states load
      _devicesMutex.release();

      // load connection statuses and states in the background
      unawaited(_loadStatesInBackground(newDevices));
      return;
    }

    notifyListeners();
    _devicesMutex.release();
  }

  Future<void> _loadStatesInBackground(List<DeviceInstance> newDevices) async {
    await _refreshConnectionStatuses(newDevices);
    try {
      await loadStates(newDevices, [], [
        dotenv.env['FUNCTION_GET_ON_OFF_STATE'] ?? '',
      ]);
    } catch (e) {
      final err = 'Could not load device states: $e';
      _logger.e(err);
      Toast.showToastNoContext(err);
    }
    // notifyListeners() is already called inside loadStates
  }

  Future<void> _refreshConnectionStatuses(List<DeviceInstance> newDevices) async {
    final futures = <Future>[
      MgwDeviceManager.updateDeviceConnectionStatusFromMgw(newDevices),
    ];
    final outsideLocalNet = newDevices
        .where((d) => d.network?.localService == null)
        .map((d) => d.id)
        .toList(growable: false);

    if (outsideLocalNet.isNotEmpty) {
      final filter = DeviceSearchFilter('')..deviceIds = outsideLocalNet;
      futures.add(
        DevicesService.getDevices(outsideLocalNet.length, 0, filter, null,
            forceBackend: true)
            .catchError((e) async {
          if (!Settings.getLocalMode()) {
            Toast.showToastNoContext('Error refreshing device status, using cache');
          }
          final cached = (await DevicesService.getDevices(
            outsideLocalNet.length, 0, filter, null,
            forceBackend: false,
          )).devices;
          for (final d in cached) {
            d.connection_state = DeviceConnectionStatus.unknown;
          }
          return DeviceInstanceWithTotal(cached, cached.length);
        }).then((ds) {
          for (final d in ds.devices) {
            newDevices.firstWhere((d2) => d2.id == d.id).connection_state =
                d.connection_state;
          }
        }),
      );
    }
    await Future.wait(futures);
  }

  // ---------------------------------------------------------------------------
  // States
  // ---------------------------------------------------------------------------

  Future<void> loadStates(
      List<DeviceInstance> devices,
      List<DeviceGroup> groups, [
        List<String>? limitToFunctionIds,
      ]) async {
    final commandCallbacks = <CommandCallback>[];

    for (final device in devices) {
      final callbacks = device.getStateFillFunctions(limitToFunctionIds);
      if (device.connection_state == DeviceConnectionStatus.offline) {
        for (final cb in callbacks) cb.callback(null);
      } else {
        commandCallbacks.addAll(callbacks);
      }
    }
    for (final group in groups) {
      group.prepareStates();
      commandCallbacks.addAll(group.getStateFillFunctions(limitToFunctionIds));
    }

    if (commandCallbacks.isEmpty) {
      _notifyEntities(devices, groups);
      return;
    }

    List<DeviceCommandResponse> result;
    try {
      result = await DeviceCommandsService.runCommands(
        commandCallbacks.map((e) => e.command).toList(growable: false),
      );
    } on ApiUnavailableException {
      const err = 'failed to loadStates: currently unavailable';
      _logger.e(err);
      Toast.showToastNoContext(err);
      result = List.filled(commandCallbacks.length, DeviceCommandResponse(200, null));
    } catch (e) {
      final err = 'failed to loadStates: $e';
      _logger.e(err);
      Toast.showToastNoContext(err);
      result = List.filled(commandCallbacks.length, DeviceCommandResponse(200, null));
    }

    assert(result.length == commandCallbacks.length);
    for (var i = 0; i < commandCallbacks.length; i++) {
      if (result[i].status_code == 200) {
        commandCallbacks[i].callback(result[i].message);
      } else {
        _logger.e('${result[i].status_code}: ${result[i].message}');
        commandCallbacks[i].callback(null);
      }
    }
    _notifyEntities(devices, groups);
  }

  /// Signals only the affected devices/groups (not the whole AppState) so their
  /// list items / detail pages rebuild without waking every other consumer.
  void _notifyEntities(List<DeviceInstance> devices, List<DeviceGroup> groups) {
    for (final d in devices) {
      d.notifyStateChanged();
    }
    for (final g in groups) {
      g.notifyStateChanged();
    }
  }

  // ---------------------------------------------------------------------------
  // Device groups
  // ---------------------------------------------------------------------------

  Future<void> loadDeviceGroups(BuildContext context) async {
    final locked = _deviceGroupsMutex.isLocked;
    await _deviceGroupsMutex.acquire();
    if (locked) {
      _deviceGroupsMutex.release();
      return;
    }
    deviceGroups.clear();
    notifyListeners();
    try {
      deviceGroups.addAll(
        await Future.wait(await DeviceGroupsService.getDeviceGroups()),
      );
    } catch (e) {
      final err = 'Could not load device groups: $e';
      _logger.e(err);
      Toast.showToastNoContext(err);
    } finally {
      _deviceGroupsMutex.release();
    }
    _deviceGroupsLoadedOnce = true;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  void clearDeviceData() {
    deviceClasses.clear();
    deviceTypes.clear();
    _deviceSearchFilter = DeviceSearchFilter.empty();
    totalDevices = 0;
    devices.clear();
    _allDevicesLoaded = false;
    _devicesLoadedOnce = false;
    _deviceOffset = 0;
    deviceGroups.clear();
    _deviceGroupsLoadedOnce = false;
  }
}