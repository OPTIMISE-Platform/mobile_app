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
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/shared/metadata_cache.dart';
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

  /// Raw pages fetched so far (before hiding inactive devices). Unlike
  /// [devices].length, this advances even on a page that filters down to
  /// nothing, so a rebuild gated on it (DeviceList's Selector) still notices.
  int get rawDevicesFetched => _deviceOffset;

  /// Upper bound for a list's itemCount while paginating. Not [totalDevices]
  /// (the server's raw, unfiltered count): hidden devices can leave
  /// devices.length permanently below it, which would add trailing blank
  /// rows instead of ending the list. The devices.length >= totalDevices
  /// branch covers tests that fill [devices] directly to match [totalDevices]
  /// without ever driving [_allDevicesLoaded] true through a real fetch.
  int get devicesListItemCount =>
      (_allDevicesLoaded || devices.length >= totalDevices)
          ? devices.length
          : devices.length + 1;

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
    } catch (e, s) {
      ErrorReporter.report('Could not get device classes', e, s);
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

  /// Type ids a fresh load did not return. Without this, a device whose type
  /// the backend does not deliver would refetch the list on every page. Kept
  /// until [forgetUnavailableDeviceTypes] or an account change.
  final Set<String> _unavailableDeviceTypeIds = {};

  /// No fresh load before this time after one failed, so an offline start
  /// does not retry on every page.
  DateTime? _deviceTypesRetryAfter;

  @visibleForTesting
  Duration deviceTypesRetryDelay = const Duration(minutes: 1);

  @visibleForTesting
  Future<List<DeviceType>> Function(Duration maxAge) fetchDeviceTypes =
      (maxAge) => DeviceTypesService.getDeviceTypes(null, maxAge);

  Future<bool> loadDeviceTypes() async {
    final locked = _deviceTypesMutex.isLocked;
    await _deviceTypesMutex.acquire();
    if (locked) {
      _deviceTypesMutex.release();
      return true;
    }
    try {
      final fetched = await fetchDeviceTypes(metadataMaxAge);
      deviceTypes.clear();
      for (final e in fetched) {
        deviceTypes[e.id] = e;
      }
    } catch (e, s) {
      ErrorReporter.report('Could not get device types', e, s);
      return false;
    } finally {
      _deviceTypesMutex.release();
    }
    notifyListeners();
    return true;
  }

  /// Only the types of the user's devices are loaded, so a type missing here
  /// means the user's devices changed since the list was cached: reload it,
  /// bypassing the cache.
  Future<void> ensureDeviceTypes(Iterable<String> typeIds) async {
    final ids = typeIds.toSet();
    bool hasMissing() => ids.any(
        (id) => !deviceTypes.containsKey(id) && !_unavailableDeviceTypeIds.contains(id));
    if (!hasMissing()) return;
    // Not via loadDeviceTypes: joining a load that is already running there
    // returns without fetching, and that load may have been served from cache.
    await _deviceTypesMutex.acquire();
    try {
      if (!hasMissing()) return;
      final retryAfter = _deviceTypesRetryAfter;
      if (retryAfter != null && DateTime.now().isBefore(retryAfter)) return;
      final List<DeviceType> fetched;
      try {
        fetched = await fetchDeviceTypes(Duration.zero);
      } catch (e, s) {
        _deviceTypesRetryAfter = DateTime.now().add(deviceTypesRetryDelay);
        // Logged only: the devices are on screen already, just without states.
        ErrorReporter.log('Could not reload device types', e, s);
        return;
      }
      _deviceTypesRetryAfter = null;
      deviceTypes.clear();
      for (final e in fetched) {
        deviceTypes[e.id] = e;
      }
      _unavailableDeviceTypeIds.addAll(ids.where((id) => !deviceTypes.containsKey(id)));
    } finally {
      _deviceTypesMutex.release();
    }
    notifyListeners();
  }

  /// Lets [ensureDeviceTypes] try again for types an earlier fresh load did
  /// not return.
  void forgetUnavailableDeviceTypes() {
    _unavailableDeviceTypeIds.clear();
    _deviceTypesRetryAfter = null;
  }

  // ---------------------------------------------------------------------------
  // Devices
  // ---------------------------------------------------------------------------

  Future<void> searchDevices(
      DeviceSearchFilter filter, [
        bool force = false,
      ]) async {
    if (!force && _deviceSearchFilter == filter) return;
    _allDevicesLoaded = false;
    notifyListeners();
    _deviceSearchFilter = filter.clone();
    _deviceOffset = 0;
    await loadDevices(null, true);
  }

  Future<void> refreshDevices() =>
      searchDevices(_deviceSearchFilter, true);

  Future<void> loadDevices([
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

    // Single release in a finally: loadingDevices is read straight off this
    // mutex, so any path out of here that skips the release leaves the list
    // spinning for the rest of the process.
    try {
      if (_allDevicesLoaded || (offset != null && offset < devices.length)) {
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
      } catch (e, s) {
        ErrorReporter.report('Could not load devices', e, s);
        notifyListeners();
        return;
      }

      _devicesLoadedOnce = true;
      // Raw, unfiltered page size and offset: hiding happens below, on this
      // page's contents, and must not change whether pagination continues.
      _allDevicesLoaded = newDevices.length < limit;
      _deviceOffset += newDevices.length;

      final showInactive =
          _deviceSearchFilter.showInactive || _deviceSearchFilter.favorites == true;
      final visibleDevices = showInactive
          ? newDevices
          : newDevices.where((d) => !d.isInactive).toList(growable: false);

      if (visibleDevices.isNotEmpty) {
        for (final d in visibleDevices) {
          if (deviceTypes[d.device_type_id] != null) {
            d.prepareStates(deviceTypes[d.device_type_id]!);
          }
        }
        devices.addAll(visibleDevices);
      }
      // Notified even when the page filtered down to nothing: devices.length
      // may be unchanged, but rawDevicesFetched always moved.
      notifyListeners();

      if (visibleDevices.isNotEmpty) {
        // Started, not awaited - it suspends on its first await, so the
        // release below still happens right after the list is on screen.
        unawaited(_loadStatesInBackground(visibleDevices));
      }
    } finally {
      _devicesMutex.release();
    }
  }

  Future<void> _loadStatesInBackground(List<DeviceInstance> newDevices) async {
    // After the list is on screen, since it may fetch; devices whose type was
    // missing get their states only now.
    final typesReady = ensureDeviceTypes(newDevices.map((d) => d.device_type_id)).then((_) {
      for (final d in newDevices) {
        final type = deviceTypes[d.device_type_id];
        if (type != null) d.prepareStates(type);
      }
    });
    await _refreshConnectionStatuses(newDevices);
    await typesReady;
    try {
      await loadStates(newDevices, [], [
        dotenv.env['FUNCTION_GET_ON_OFF_STATE'] ?? '',
      ]);
    } catch (e, s) {
      ErrorReporter.report('Could not load device states', e, s);
    }
    // notifyListeners() is already called inside loadStates
  }

  /// Copies the connection state of [source] onto the matching entries of
  /// [target] and tells each one it changed.
  ///
  /// The notification is the point: the list listens per device, so a state
  /// written without it stays invisible until something else rebuilds the whole
  /// list - which is the slower states load right after, or nothing at all.
  @visibleForTesting
  static void applyConnectionStates(
      List<DeviceInstance> target, List<DeviceInstance> source) {
    for (final d in source) {
      final match = target.where((t) => t.id == d.id);
      if (match.isEmpty) continue;
      final device = match.first;
      if (device.connection_state == d.connection_state) continue;
      device.connection_state = d.connection_state;
      device.notifyStateChanged();
    }
  }

  Future<void> _refreshConnectionStatuses(List<DeviceInstance> newDevices) async {
    final futures = <Future>[
      MgwDeviceManager.updateDeviceConnectionStatusFromMgw(newDevices),
    ];
    final outsideLocalNet = newDevices
        .where((d) => d.network?.localGatewayHosts?.isNotEmpty != true)
        .map((d) => d.id)
        .toList(growable: false);

    if (outsideLocalNet.isNotEmpty) {
      final filter = DeviceSearchFilter('')..deviceIds = outsideLocalNet;
      futures.add(
        DevicesService.getDevices(outsideLocalNet.length, 0, filter, null,
            forceBackend: true)
            .catchError((Object e, StackTrace s) async {
          if (!Settings.getLocalMode()) {
            ErrorReporter.report(
                'Error refreshing device status, using cache', e, s);
          }
          final cached = (await DevicesService.getDevices(
            outsideLocalNet.length, 0, filter, null,
            forceBackend: false,
          )).devices;
          for (final d in cached) {
            d.connection_state = DeviceConnectionStatus.unknown;
          }
          return DeviceInstanceWithTotal(cached, cached.length);
        }).then((ds) => applyConnectionStates(newDevices, ds.devices)),
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
        for (final cb in callbacks) {
          cb.callback(null);
        }
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
    } catch (e, s) {
      // One catch: the two used to differ only in their message, and the one
      // on ApiUnavailableException never ran anyway - that exception only ever
      // arrives wrapped in a DioException.
      ErrorReporter.report('failed to loadStates', e, s);
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

  Future<void> loadDeviceGroups() async {
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
    } catch (e, s) {
      ErrorReporter.report('Could not load device groups', e, s);
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
    forgetUnavailableDeviceTypes();
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