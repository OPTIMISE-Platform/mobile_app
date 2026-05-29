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
import 'package:logger/logger.dart';
import 'package:mobile_app/mixins/data_mixin.dart';
import 'package:mobile_app/mixins/device_mixin.dart';
import 'package:mobile_app/mixins/network_mixin.dart';
import 'package:mobile_app/mixins/notification_mixin.dart';
import 'package:mobile_app/models/exception_log_element.dart';
import 'package:mobile_app/native_pipe.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/services/device_classes.dart';
import 'package:mobile_app/services/device_groups.dart';
import 'package:mobile_app/services/locations.dart';
import 'package:mobile_app/services/networks.dart';
import 'package:mobile_app/services/smart_service.dart';
import 'package:mobile_app/shared/get_broadcast_channel.dart';
import 'package:mobile_app/widgets/shared/toast.dart';
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

  static final _logger = Logger(printer: SimplePrinter());

  bool _initialized = false;

  bool get loggedIn => Auth().loggedIn;
  bool get loggingIn => Auth().loggingIn;
  bool get initialized => _initialized;

  AppState._internal() {
    WidgetsBinding.instance.addObserver(this);
    if (kIsWeb) {
      getBroadcastChannel('optimise-mobile-app').onMessage.listen((event) {
        // ignore: invalid_use_of_protected_member
        handleQueuedMessages();
      });
    }
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

    try {
      await Future.wait([
        loadDeviceClasses(),
        loadDeviceTypes(),
        loadNestedFunctions(),
        loadAspects(),
        loadConcepts(),
        loadCharacteristics(),
        initMessaging(),
        loadStoredMGWs(),
      ]);
    } finally {
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
    CacheHelper.clearCache();
  }

  final _refreshPressedController = StreamController.broadcast();

  Stream get refreshPressed => _refreshPressedController.stream;

  void pushRefresh() => _refreshPressedController.add(null);

  List<bool> setAndGetDisabledTabs() {
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
    return disabledList;
  }

  // ---------------------------------------------------------------------------
  // notifyListeners passthrough (required by some call sites)
  // ---------------------------------------------------------------------------

  @override
  // ignore: unnecessary_overrides
  void notifyListeners() => super.notifyListeners();
}