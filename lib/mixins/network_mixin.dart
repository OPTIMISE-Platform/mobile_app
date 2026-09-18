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


import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/location.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/services/locations.dart';
import 'package:mobile_app/services/mgw/discovery.dart';
import 'package:mobile_app/services/mgw/reachability.dart';
import 'package:mobile_app/services/mgw/storage.dart';
import 'package:mobile_app/services/mgw_device_manager.dart';
import 'package:mobile_app/services/networks.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mutex/mutex.dart';

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
  final _mergeMutex = Mutex();

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
    try {
      networks.clear();
      notifyListeners();
      try {
        networks.addAll(await NetworksService.getNetworks());
      } catch (e) {
        ErrorReporter.report('Could not load networks', e);
      }
      _networkByLocalId = null; // networks changed — drop the cached lookup
      await mergeGatewaysWithNetworks();
      _assignNetworksToDevicesAndGroups();
      await MgwDeviceManager.updateDeviceConnectionStatusFromMgw(devices);
      notifyListeners();
    } finally {
      // Released whatever happened above: a lock left behind here is not
      // recoverable without an app restart - loadingNetworks() stays true, the
      // tab shows its spinner for good and every later load blocks on acquire.
      _networksMutex.release();
    }
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

  Future<void> loadLocations() async {
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
      ErrorReporter.report('Could not load locations', e);
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

  bool _discovering = false;

  /// Refreshes the addresses of the paired gateways and re-links them to their
  /// networks.
  ///
  /// Discovery only keeps a known gateway's address current; it cannot add one,
  /// because the core advertises its own core id and never the network it
  /// serves, so the link is only ever established when a gateway is added.
  Future<void> manageNetworkDiscovery() async {
    if (_discovering) return;
    _discovering = true;
    // Called on resume, which is when the device may have joined a different
    // network - so the reachability answers from before have to go.
    MgwReachability.forget();
    try {
      final stored = await MgwStorage.LoadPairedMGWs();
      // Only a gateway that was discovered once can be recognised again, so
      // with none of them there is nothing an mDNS scan could update - and it
      // would still bind a socket and join a multicast group on every resume.
      if (stored.any((mgw) => mgw.coreId.isNotEmpty)) {
        final found = await MgwDiscoveryService.discover();
        if (found.isNotEmpty) await _refreshGatewayAddresses(stored, found);
      }
    } catch (e) {
      _logger.e('NetworkMixin: gateway discovery failed: $e');
    } finally {
      _discovering = false;
    }
    await mergeGatewaysWithNetworks();
  }

  Future<void> _refreshGatewayAddresses(
      List<MGW> stored, List<DiscoveredGateway> found) async {
    var changed = false;
    for (final mgw in stored) {
      if (mgw.coreId.isEmpty) continue;
      final matches = found.where((g) => g.coreId == mgw.coreId);
      if (matches.isEmpty) continue;
      final match = matches.first;
      if (match.ip.isEmpty || match.ip == mgw.ip) continue;
      _logger.d(
          'NetworkMixin: gateway ${mgw.coreId} moved from ${mgw.ip} to ${match.ip}');
      mgw.ip = match.ip;
      mgw.hostname = match.hostname;
      changed = true;
    }
    if (!changed) return;
    await MgwStorage.ReplacePairedMGWs(stored);
    // gateways holds its own instances, so without this the list and the detail
    // page keep addressing the gateway where it no longer is.
    await loadStoredMGWs();
  }

  /// Attaches every paired gateway that is usable right now to the network it
  /// was bound to when it was added. A network without one keeps
  /// [Network.localGatewayHosts] null and is served from the cloud.
  ///
  /// The status check is what makes a gateway in a different local network - or
  /// one that no longer knows this device - harmless: it stays paired, but
  /// nothing is routed to it until it answers an authenticated request.
  Future<void> mergeGatewaysWithNetworks() async {
    // Serialized and assigned in one go: the probes below take up to a second,
    // and clearing the lists before them would leave every reader without a
    // local gateway meanwhile - and two overlapping runs would each append.
    await _mergeMutex.protect(() async {
      final storedMGWs = await MgwStorage.LoadPairedMGWs();
      final candidates = storedMGWs
          .where((mgw) => mgw.networkId.isNotEmpty && mgw.ip.isNotEmpty)
          .toList();

      final hostsByNetwork = <String, List<String>>{};
      if (candidates.isNotEmpty) {
        final usable = (await MgwReachability.usableAmong(
                candidates.map((mgw) => MapEntry(mgw.ip, mgw.networkId))))
            .toSet();
        for (final mgw in candidates) {
          if (!usable.contains(mgw.ip)) {
            _logger.d(
                'NetworkMixin: gateway ${mgw.ip} is not usable, using the cloud');
            continue;
          }
          final hosts = hostsByNetwork.putIfAbsent(mgw.networkId, () => []);
          if (!hosts.contains(mgw.ip)) hosts.add(mgw.ip);
        }
      }

      for (final n in networks) {
        n.localGatewayHosts = hostsByNetwork[n.id];
      }
    });
    notifyListeners();
  }

  void clearNetworkData() {
    networks.clear();
    _networkByLocalId = null;
    locations.clear();
    gateways.clear();
  }
}