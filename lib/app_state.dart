/*
 * Copyright 2022 InfAI (CC SES)
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
import 'package:mobile_app/mixins/data_mixin.dart';
import 'package:mobile_app/mixins/device_mixin.dart';
import 'package:mobile_app/mixins/network_mixin.dart';
import 'package:mobile_app/mixins/notification_mixin.dart';
import 'package:mobile_app/native_pipe.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/device_classes.dart';
import 'package:mobile_app/services/device_groups.dart';
import 'package:mobile_app/services/locations.dart';
import 'package:mobile_app/services/networks.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/services/smart_service.dart';
import 'package:mobile_app/widgets/tabs/nav.dart';

class AppState extends ChangeNotifier
    with
        DeviceMixin,
        NetworkMixin,
        NotificationMixin,
        DataMixin,
        WidgetsBindingObserver {
  static final _instance = AppState._internal();

  factory AppState() => _instance;

  bool _initialized = false;

  bool get loggedIn => Auth().loggedIn;
  bool get loggingIn => Auth().loggingIn;
  bool get initialized => _initialized;

  AppState._internal() {
    WidgetsBinding.instance.addObserver(this);
    manageNetworkDiscovery();
    NativePipe.init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    handleQueuedMessages();
    manageNetworkDiscovery();
  }

  @override
  Future<void> ensureInitialized() async {
    if (!_initialized) await init();
  }

  Future<void> init() async {
    if (_initialized) return;
    final startTime = DateTime.now();

    try {
      unawaited(initMessaging());
      await Future.wait([
        loadDeviceClasses(),
        loadDeviceTypes(),
        loadNestedFunctions(),
        loadAspects(),
        loadConcepts(),
        loadCharacteristics(),
        loadStoredMGWs(),
      ]);
    } finally {
      debugPrint('AppState init took ${DateTime.now().difference(startTime)}');
      _initialized = true;
      notifyListeners();
    }
  }

  Future<void> onLogout() async {
    await clearNotificationData();
    clearDeviceData();
    clearNetworkData();
    clearData();
    _initialized = false;
    // No clearCache here: the only caller (Auth._cleanup) has already awaited
    // it — this unawaited second run raced whatever a re-login started.
  }

  final _refreshPressedController = StreamController.broadcast();

  Stream get refreshPressed => _refreshPressedController.stream;

  void pushRefresh() => _refreshPressedController.add(null);

  /// Reloads the in-memory metadata maps and notifies the open tabs to reload
  /// their data. Devices, groups, networks and locations are covered by the
  /// tabs' [refreshPressed] listeners; the metadata maps are loaded only once
  /// at [init] and would otherwise keep their stale entries until an app
  /// restart. The loaders swap their maps only after a successful fetch, so
  /// readers never see them empty mid-reload.
  ///
  /// [onProgress] reports the fraction of completed reload tasks (0..1).
  /// Throws when any loader failed, after all of them have finished.
  Future<void> reloadMetadata({void Function(double progress)? onProgress}) async {
    final tasks = <Future<bool>>[
      loadDeviceClasses(),
      loadDeviceTypes(),
      loadNestedFunctions(),
      loadAspects(),
      loadConcepts(),
      loadCharacteristics(),
    ];
    var done = 0;
    final results = await Future.wait(tasks.map((t) => t.whenComplete(() {
          done++;
          onProgress?.call(done / tasks.length);
        })));
    notifyListeners();
    pushRefresh();
    // The loaders toast and swallow their own errors; without this the caller
    // would report success over stale maps.
    if (results.contains(false)) {
      throw Exception("not all metadata could be reloaded");
    }
  }

  // Memoized result of setAndGetDisabledTabs(). Recomputing walks every nav
  // item and calls the services' isAvailable()/isListAvailable() checks, each
  // of which parses a URI and scans the networks (~2ms a piece). This used to
  // run on every notifyListeners(); now we only redo it when one of the inputs
  // the result depends on actually changes.
  List<bool>? _disabledTabsCache;
  String? _disabledTabsInputSig;

  /// Cheap signature of the inputs [setAndGetDisabledTabs] depends on, without
  /// running the expensive availability checks.
  String _disabledTabsInput() {
    final sb = StringBuffer()
      ..write(locations.length)
      ..write(',')
      ..write(deviceGroups.length)
      ..write(',')
      ..write(networks.length)
      ..write(',')
      ..write(deviceClasses.length)
      ..write(',')
      ..write(Settings.getLocalMode() ? '1' : '0')
      ..write(',')
      ..write(Settings.getApiUrl() ?? '');
    return sb.toString();
  }

  List<bool> setAndGetDisabledTabs() {
    final input = _disabledTabsInput();
    final cached = _disabledTabsCache;
    if (cached != null && _disabledTabsInputSig == input) {
      return cached;
    }

    final disabledList = List.generate(navItems.length, (_) => true);
    for (final navItem in navItems) {
      switch (navItem.index) {
        case tabLocations:
          navItem.disabled =
              locations.isEmpty && !LocationService.isListAvailable();
          break;
        case tabGroups:
          navItem.disabled =
              deviceGroups.isEmpty && !DeviceGroupsService.isListAvailable();
          break;
        case tabNetworks:
          navItem.disabled =
              networks.isEmpty && !NetworksService.isAvailable();
          break;
        case tabClasses:
          navItem.disabled =
              deviceClasses.isEmpty && !DeviceClassesService.isAvailable();
          break;
        case tabSmartServices:
        case tabDashboard:
          navItem.disabled = !SmartServiceService.isAvailable();
          break;
        default:
          navItem.disabled = false;
      }
      disabledList[navItem.index] = navItem.disabled;
    }

    _disabledTabsInputSig = input;
    _disabledTabsCache = disabledList;
    return disabledList;
  }

  // ---------------------------------------------------------------------------
  // notifyListeners passthrough (required by some call sites)
  // ---------------------------------------------------------------------------

  @override
  // ignore: unnecessary_overrides
  void notifyListeners() => super.notifyListeners();
}