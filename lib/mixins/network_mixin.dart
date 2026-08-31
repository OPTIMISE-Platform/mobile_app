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

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/location.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/services/locations.dart';
import 'package:mobile_app/services/mgw/storage.dart';
import 'package:mobile_app/services/mgw_device_manager.dart';
import 'package:mobile_app/services/networks.dart';
import 'package:mobile_app/widgets/shared/toast.dart';
import 'package:mutex/mutex.dart';
import 'package:nsd/nsd.dart';

mixin NetworkMixin on ChangeNotifier {
  static final _logger = Logger(printer: SimplePrinter());

  final List<Network> networks = [];
  final _networksMutex = Mutex();

  /// Memoized local_id -> Network lookup, rebuilt lazily after [networks]
  /// change. Avoids an O(networks) scan per device in the DeviceInstance
  /// constructor — which also runs on every Isar cache read.
  Map<String, Network>? _networkByLocalId;

  final List<Location> locations = [];
  final _locationsMutex = Mutex();

  final List<MGW> gateways = [];
  final _gatewaysMutex = Mutex();

  Discovery? _discovery;

  // Subclasses must expose these so network loading can update connection state.
  List<DeviceInstance> get devices;
  List<DeviceGroup> get deviceGroups;

  bool loadingNetworks() => _networksMutex.isLocked;

  Future<void> loadNetworks(BuildContext context) async {
    final locked = _networksMutex.isLocked;
    await _networksMutex.acquire();
    if (locked) {
      _networksMutex.release();
      return;
    }
    networks.clear();
    notifyListeners();
    try {
      networks.addAll(await NetworksService.getNetworks());
    } catch (e) {
      final err = 'Could not load networks: $e';
      _logger.e(err);
      Toast.showToastNoContext(err);
    }
    _networkByLocalId = null; // networks changed — drop the cached lookup
    _mergeDiscoveredServicesWithNetworks();
    _assignNetworksToDevicesAndGroups();
    await MgwDeviceManager.updateDeviceConnectionStatusFromMgw(devices);
    notifyListeners();
    _networksMutex.release();
  }

  /// O(1) local_id -> Network lookup backed by [_networkByLocalId].
  Network? networkForLocalId(String localId) =>
      (_networkByLocalId ??= _buildNetworkByLocalId())[localId];

  Map<String, Network> _buildNetworkByLocalId() {
    final map = <String, Network>{};
    for (final network in networks) {
      final ids = network.device_local_ids;
      if (ids == null) continue;
      for (final localId in ids) {
        // putIfAbsent preserves the first-match semantics of the previous
        // indexWhere-based lookup.
        map.putIfAbsent(localId, () => network);
      }
    }
    return map;
  }

  void _assignNetworksToDevicesAndGroups() {
    // DeviceInstance.network is computed on demand now, so only device groups
    // still need an explicit assignment here.
    for (final network in networks) {
      for (final group in deviceGroups) {
        if (group.device_ids.every((id) =>
            (network.device_ids ?? <String>[]).contains(id.substring(0, 57)))) {
          group.network = network;
        }
      }
    }
  }

  bool loadingLocations() => _locationsMutex.isLocked;

  Future<void> loadLocations(BuildContext context) async {
    final locked = _locationsMutex.isLocked;
    await _locationsMutex.acquire();
    if (locked) {
      _locationsMutex.release();
      return;
    }
    locations.clear();
    notifyListeners();
    try {
      locations.addAll(await Future.wait(await LocationService.getLocations()));
    } catch (e) {
      final err = 'Could not load locations: $e';
      _logger.e(err);
      Toast.showToastNoContext(err);
    } finally {
      _locationsMutex.release();
    }
    notifyListeners();
  }

  Future<void> loadStoredMGWs() async {
    _logger.d('NetworkMixin: loading stored MGWs');
    await _gatewaysMutex.acquire();
    final storedMGWs = await MgwStorage.LoadPairedMGWs();
    gateways
      ..clear()
      ..addAll(storedMGWs);
    _gatewaysMutex.release();
    notifyListeners();
  }

  bool _discoveryStarting = false;

  Future<void> manageNetworkDiscovery() async {
    if (kIsWeb) return;
    if (_discovery != null || _discoveryStarting) return;
    _discoveryStarting = true;

    try {
      _discovery = await startDiscovery('_snrgy._tcp', ipLookupType: IpLookupType.any);
      _discovery!.addListener(_mergeDiscoveredServicesWithNetworks);
    } finally {
      _discoveryStarting = false;
    }
  }

  Future<void> _mergeDiscoveredServicesWithNetworks() async {
    final storedMGWs = await MgwStorage.LoadPairedMGWs();
    for (final n in networks) {
      n.localService = null;
    }
    if (storedMGWs.isEmpty) return;
    _discovery?.services.forEach((service) {
      final serial = utf8.decode(
        (service.txt?['serial'] ?? Uint8List(0)).map((e) => e.toInt()).toList(),
      );
      final nI = networks.indexWhere((n) => n.id == serial);
      if (nI == -1) return;
      final nG = storedMGWs.indexWhere((mgw) => mgw.coreId == networks[nI].id);
      if (nG == -1) return;
      networks[nI].localService ??= [];
      networks[nI].localService?.add(service);
    });
  }

  void clearNetworkData() {
    networks.clear();
    _networkByLocalId = null;
    locations.clear();
    gateways.clear();
  }
}