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
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio_http2_adapter/dio_http2_adapter.dart';
import 'package:eraser/eraser.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/exceptions/api_unavailable_exception.dart';
import 'package:mobile_app/models/aspect.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/function.dart';
import 'package:mobile_app/models/location.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/models/notification.dart' as app;
import 'package:mobile_app/services/app_update.dart';
import 'package:mobile_app/services/aspects.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/services/characteristics.dart';
import 'package:mobile_app/services/concepts.dart';
import 'package:mobile_app/services/device_classes.dart';
import 'package:mobile_app/services/device_commands.dart';
import 'package:mobile_app/services/device_groups.dart';
import 'package:mobile_app/services/device_types.dart';
import 'package:mobile_app/services/device_types_perm_search.dart';
import 'package:mobile_app/services/devices.dart';
import 'package:mobile_app/services/fcm_token.dart';
import 'package:mobile_app/services/functions.dart';
import 'package:mobile_app/services/locations.dart';
import 'package:mobile_app/services/mgw/storage.dart';
import 'package:mobile_app/services/mgw_device_manager.dart';
import 'package:mobile_app/services/networks.dart';
import 'package:mobile_app/services/notifications.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/services/smart_service.dart';
import 'package:mobile_app/shared/get_broadcast_channel.dart';
import 'package:mobile_app/shared/remote_message_encoder.dart';
import 'package:mobile_app/widgets/notifications/notification_list.dart';
import 'package:mobile_app/widgets/shared/toast.dart';
import 'package:mobile_app/widgets/tabs/nav.dart';
import 'package:mutex/mutex.dart';
import 'package:nsd/nsd.dart';

import 'package:mobile_app/models/characteristic.dart';
import 'package:mobile_app/models/concept.dart';
import 'package:mobile_app/models/device_class.dart';
import 'package:mobile_app/models/device_command_response.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/models/exception_log_element.dart';
import 'package:mobile_app/native_pipe.dart';

const notificationUpdateType = "put notification";
const notificationDeleteManyType = "delete notifications";
const notificationReleaseInfoType = "release_info";
const messageKey = "messages";

class AppState extends ChangeNotifier with WidgetsBindingObserver {
  static final _instance = AppState._internal();

  factory AppState() => _instance;

  AppState._internal() {
    WidgetsBinding.instance.addObserver(this);
    if (kIsWeb) {
      // receive broadcasts from service worker
      getBroadcastChannel("optimise-mobile-app").onMessage.listen((event) {
        _handleRemoteMessageCommand(event.data["data"]);
      });
    }
    _manageNetworkDiscovery();
    NativePipe.init();
  }

  static final connectionManager = ConnectionManager();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      handleQueuedMessages();
      _manageNetworkDiscovery()
          .then((_) => _mergeDiscoveredServicesWithNetworks());
    }
  }

  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  static const _storage = FlutterSecureStorage(aOptions: AndroidOptions(
    encryptedSharedPreferences: true,
  ));

  static final _messageMutex = Mutex();

  static queueRemoteMessage(RemoteMessage message) async {
    await _messageMutex.acquire();
    _logger.d("Queuing message ${message.messageId}");
    final remoteMessageMap = remoteMessageToMap(message);

    switch (remoteMessageMap["data"]["type"]) {
      case notificationUpdateType:
        final updatedNotification = app.Notification.fromJson(
            json.decode(remoteMessageMap["data"]["payload"]));
        if (updatedNotification.isRead) {
          await Eraser.clearAppNotificationsByTag(updatedNotification.id);
        }
        break;
      case notificationDeleteManyType:
        List<dynamic> ids = json.decode(remoteMessageMap["data"]["payload"]);
        ids.forEach((id) => Eraser.clearAppNotificationsByTag(id));
        break;
    }

    String? read = await _storage.read(key: messageKey);
    final List list;

    if (read != null) {
      list = json.decode(read);
    } else {
      list = [];
    }

    list.add(remoteMessageMap);

    await _storage.write(key: messageKey, value: json.encode(list));
    _messageMutex.release();
  }

  FirebaseMessaging messaging = FirebaseMessaging.instance;
  String? fcmToken;
  final _fcmTokenMutex = Mutex();

  bool _initialized = false;

  final Map<String, DeviceClass> deviceClasses = {};
  final Mutex _deviceClassesMutex = Mutex();

  final Map<String, DeviceTypePermSearch> deviceTypesPermSearch = {};
  final Mutex _deviceTypesPermSearchMutex = Mutex();

  final Map<String, DeviceType> deviceTypes = {};

  final Map<String, NestedFunction> nestedFunctions = {};
  final Mutex _nestedFunctionsMutex = Mutex();

  final Map<String, Concept> concepts = {};
  final Mutex _conceptsMutex = Mutex();

  final Map<String, Characteristic> characteristics = {};
  final Mutex _characteristicsMutex = Mutex();

  DeviceSearchFilter _deviceSearchFilter = DeviceSearchFilter.empty();

  int totalDevices = 0;
  final Mutex _totalDevicesMutex = Mutex();

  final List<DeviceInstance> devices = <DeviceInstance>[];
  final Mutex _devicesMutex = Mutex();
  bool _allDevicesLoaded = false;
  int _deviceOffset = 0;

  final List<DeviceGroup> deviceGroups = <DeviceGroup>[];
  final Mutex _deviceGroupsMutex = Mutex();

  final List<Location> locations = <Location>[];
  final Mutex _locationsMutex = Mutex();

  final List<Network> networks = [];
  final Mutex _networksMutex = Mutex();

  final List<MGW> gateways = [];
  final Mutex _gatewaysMutex = Mutex();

  final Map<String, Aspect> aspects = {};
  final Mutex _aspectsMutex = Mutex();

  List<app.Notification> notifications = [];
  final Mutex _notificationsMutex = Mutex();
  bool _notificationInited = false;
  String? _messageIdToDisplay;

  bool get loggedIn => Auth().loggedIn;

  bool get loggingIn => Auth().loggingIn;

  bool get initialized => _initialized;

  init() async {
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageInteraction);
    final List<Future> futures = [
      loadDeviceClasses(),
      loadDeviceTypes(),
      loadNestedFunctions(),
      loadAspects(),
      loadConcepts(),
      loadCharacteristics(),
      initMessaging(),
      loadStoredMGWs()
    ];
    try {
      await Future.wait(futures);
    } catch (e) {
      ExceptionLogElement.Log(e.toString());
      Toast.showToastNoContext("Could not initialize");
    }
    _initialized = true;
  }

  loadDeviceClasses() async {
    final locked = _deviceClassesMutex.isLocked;
    await _deviceClassesMutex.acquire();
    if (locked) {
      return deviceClasses;
    }
    deviceClasses.clear();
    notifyListeners();
    try {
      for (var element in (await DeviceClassesService.getDeviceClasses())) {
        deviceClasses[element.id] = element;
      }
    } catch (e) {
      final err = "Coud not get device classes $e";
      _logger.e(err);
      Toast.showToastNoContext(err);
    }
    notifyListeners();
    _deviceClassesMutex.release();
  }

  bool get loadingDeviceClasses {
    return _deviceClassesMutex.isLocked;
  }

  loadDeviceTypes() async {
    final locked = _deviceTypesPermSearchMutex.isLocked;
    await _deviceTypesPermSearchMutex.acquire();
    if (locked) {
      return deviceTypesPermSearch;
    }
    try {
      for (var element
          in (await DeviceTypesPermSearchService.getDeviceTypes())) {
        deviceTypesPermSearch[element.id] = element;
      }
    } catch (e) {
      final err = "Could not get device types $e";
      _logger.e(err);
      Toast.showToastNoContext(err);
    }
    notifyListeners();
    _deviceTypesPermSearchMutex.release();
  }

  loadNestedFunctions() async {
    final locked = _nestedFunctionsMutex.isLocked;
    await _nestedFunctionsMutex.acquire();
    if (locked) {
      return nestedFunctions;
    }
    try {
      for (var element in (await FunctionsService.getNestedFunctions())) {
        nestedFunctions[element.id] = element;
      }
    } catch (e) {
      final err = "Could not get nested functions $e";
      _logger.e(err);
      Toast.showToastNoContext(err);
    }
    notifyListeners();
    _nestedFunctionsMutex.release();
  }

  loadConcepts() async {
    final locked = _conceptsMutex.isLocked;
    await _conceptsMutex.acquire();
    if (locked) {
      return concepts;
    }
    try {
      for (var element in (await ConceptsService.getConcepts())) {
        concepts[element.id] = element;
      }
    } catch (e) {
      final err = "Could not get concepts $e";
      _logger.e(err);
      Toast.showToastNoContext(err);
    }
    notifyListeners();
    _conceptsMutex.release();
  }

  loadCharacteristics() async {
    final locked = _characteristicsMutex.isLocked;
    await _characteristicsMutex.acquire();
    if (locked) {
      return characteristics;
    }
    try {
      for (var element in (await CharacteristicsService.getCharacteristics())) {
        characteristics[element.id] = element;
      }
    } catch (e) {
      final err = "Could not get characteristics $e";
      _logger.e(err);
      Toast.showToastNoContext(err);
    }
    notifyListeners();
    _characteristicsMutex.release();
  }

  updateTotalDevices() async {
    await _totalDevicesMutex.protect(() async {
      try {
        final total = await DevicesService.getTotalDevices(_deviceSearchFilter);
        if (total != totalDevices) {
          totalDevices = total;
          notifyListeners();
        }
      } catch (e) {
        final err = "Could not get total devices $e";
        _logger.e(err);
        Toast.showToastNoContext(err);
      }
    });
  }

  Future searchDevices(DeviceSearchFilter filter, BuildContext context,
      [bool force = false]) async {
    if (!force && _deviceSearchFilter == filter) {
      return;
    }
    _allDevicesLoaded = false;
    notifyListeners();
    _deviceSearchFilter = filter.clone();
    _deviceOffset = 0;
    await updateTotalDevices();
    await loadDevices(context, null, true);
  }

  refreshDevices(BuildContext context) async {
    await searchDevices(_deviceSearchFilter, context, true);
  }

  loadDevices(BuildContext context, [int? offset, bool clear = false]) async {
    if (_allDevicesLoaded) {
      return;
    }
    await _devicesMutex.acquire();

    if (_allDevicesLoaded || (offset != null && offset < devices.length)) {
      _devicesMutex.release();
      notifyListeners(); // missing loadingDevices() change otherwise
      return;
    }

    if (clear) {
      devices.clear();
    }

    if (!_initialized) {
      await init();
    }

    late final List<DeviceInstance> newDevices;
    const limit = 50;
    try {
      newDevices = await DevicesService.getDevices(limit, _deviceOffset,
          _deviceSearchFilter, devices.isNotEmpty ? devices.last : null);
    } catch (e) {
      _logger.e("Could not get devices: $e");
      Toast.showToastNoContext("Could not load devices");
      notifyListeners(); // missing loadingDevices() change otherwise
      _devicesMutex.release();
      return;
    }
    _allDevicesLoaded = newDevices.length < limit;
    _deviceOffset += newDevices.length;
    if (newDevices.isNotEmpty) {
      for (int i = 0; i < newDevices.length; i++) {
        await loadDeviceType(newDevices[i].device_type_id);
        newDevices[i].prepareStates(deviceTypes[newDevices[i].device_type_id]!);
      }

      final connectionStatusFutures = <Future>[
        MgwDeviceManager.updateDeviceConnectionStatusFromMgw(newDevices),
      ];

      // update connection status for devices outside of local network
      final refreshDeviceIds = newDevices
          .where((element) => element.network?.localService == null)
          .map((e) => e.id)
          .toList(growable: false);
      if (refreshDeviceIds.isNotEmpty) {
        final refreshFilter = DeviceSearchFilter("");
        refreshFilter.deviceIds = refreshDeviceIds;

        connectionStatusFutures.add(DevicesService.getDevices(
                refreshDeviceIds.length, 0, refreshFilter, null,
                forceBackend: true)
            .catchError(( e) async {
          if (!Settings.getLocalMode()) {
            Toast.showToastNoContext(
                "Error refreshing device status, using cache");
          }
          final devices = await DevicesService.getDevices(
              refreshDeviceIds.length, 0, refreshFilter, null,
              forceBackend: false);
          devices.forEach((element) =>
              element.connectionStatus = DeviceConnectionStatus.unknown);
          return devices;
        }).then((ds) => ds.forEach((d) => newDevices
                .firstWhere((d2) => d2.id == d.id)
                .annotations = d.annotations)));
      }
      try {
        await Future.wait(connectionStatusFutures);
        await loadStates(newDevices, [], [
          dotenv.env['FUNCTION_GET_ON_OFF_STATE'] ?? ''
        ]); // need to know which devices are online first
        devices.addAll(newDevices);
      } catch (e) {
        final err = "Could not get devices: $e";
        _logger.e(err);
        Toast.showToastNoContext(err);
      }
    }
    if (totalDevices <= _deviceOffset) {
      await updateTotalDevices(); // when loadDevices called directly
    }
    notifyListeners();
    _devicesMutex.release();
  }

  bool get loadingDevices {
    return _totalDevicesMutex.isLocked || _devicesMutex.isLocked;
  }

  bool get allDevicesLoaded {
    return _allDevicesLoaded;
  }

  Future<void> loadDeviceType(String id, [bool force = false]) async {
    if (!force && deviceTypes.containsKey(id)) {
      return;
    }
    try {
      final t = await DeviceTypesService.getDeviceType(id);
      if (t == null) {
        return;
      }
      deviceTypes[id] = t;
    } catch (e) {
      final err = "Could not load device type $e";
      _logger.e(err);
      Toast.showToastNoContext(err);
    }
  }

  loadStates(List<DeviceInstance> devices, List<DeviceGroup> groups,
      [List<String>? limitToFunctionIds]) async {
    final List<CommandCallback> commandCallbacks = [];
    for (var element in devices) {
      final callbacks = element.getStateFillFunctions(limitToFunctionIds);
      if (element.connectionStatus == DeviceConnectionStatus.offline) {
        callbacks.forEach((element) => element.callback(null));
      } else {
        commandCallbacks.addAll(callbacks);
      }
    }
    for (var element in groups) {
      element.prepareStates();
      commandCallbacks
          .addAll(element.getStateFillFunctions(limitToFunctionIds));
    }
    if (commandCallbacks.isEmpty) {
      notifyListeners();
      return;
    }
    List<DeviceCommandResponse> result;
    try {
      result = await DeviceCommandsService.runCommands(
          commandCallbacks.map((e) => e.command).toList(growable: false));
    } on ApiUnavailableException {
      const err = "failed to loadStates: currently unavailable";
      _logger.e(err);
      Toast.showToastNoContext(err);
      result = [];
      commandCallbacks
          .forEach((_) => result.add(DeviceCommandResponse(200, null)));
    } catch (e) {
      final err = "failed to loadStates: $e";
      _logger.e(err);
      Toast.showToastNoContext(err);
      result = [];
      commandCallbacks
          .forEach((_) => result.add(DeviceCommandResponse(200, null)));
    }
    assert(result.length == commandCallbacks.length);
    for (var i = 0; i < commandCallbacks.length; i++) {
      if (result[i].status_code == 200) {
        commandCallbacks[i].callback(result[i].message);
      } else {
        _logger.e("${result[i].status_code}: ${result[i].message}");
        commandCallbacks[i].callback(null);
      }
    }
    notifyListeners();
  }

  loadNotifications(BuildContext? context) async {
    final locked = _notificationsMutex.isLocked;
    await _notificationsMutex.acquire();
    if (locked) {
      return notifications;
    }
    notifications.clear();
    await _storage.delete(
        key: messageKey); // clean up any queued messages of previous instances

    const limit = 10000;
    int offset = 0;
    app.NotificationResponse? response;
    try {
      do {
        try {
          response = await NotificationsService.getNotifications(limit, offset);
        } catch (e) {
          final err = "Could not load notifications: $e";
          _logger.e(err);
          Toast.showToastNoContext(err);
          return;
        }
        final tmp = response?.notifications.reversed.toList() ??
            []; // got reverse ordered batches form api
        tmp.addAll(notifications);
        notifications = tmp;
        offset += response?.notifications.length ?? 0;
        notifyListeners();
      } while (response != null && response.notifications.length == limit);
    } catch (e) {
      const err = "Could not load notifications";
      if (context != null) Toast.showToastNoContext(err);
      _logger.e("$err: $e");
    } finally {
      _notificationsMutex.release();
    }
  }

  updateNotifications(BuildContext context, int index) async {
    try {
      await NotificationsService.setNotification(notifications[index]);
    } catch (e) {
      final err = "Could not update notification $e";
      _logger.e(err);
      Toast.showToastNoContext(err);
    }
    notifyListeners();
  }

  deleteNotifications(BuildContext context, List<String> ids) async {
    try {
      await NotificationsService.deleteNotifications(ids);
    } catch (e) {
      _logger.e(e.toString());
      Toast.showToastNoContext("Could not delete notifications");
    }
    // notifications.removeAt(index);
    // notifyListeners(); Expect change propagation through FCM
  }

  deleteAllNotifications(BuildContext context) async {
    try {
      await NotificationsService.deleteNotifications(
          notifications.map((e) => e.id).toList(growable: false));
    } catch (e) {
      _logger.e(e.toString());
      Toast.showToastNoContext("Could not delete notifications");
    }
    // notifications.clear();
    // notifyListeners(); Expect change propagation through FCM
  }

  initNotifications(BuildContext context) {
    if (_notificationInited) {
      return;
    }
    _notificationInited = true;
    loadNotifications(context);
  }

  initMessaging() async {
    try {
      await messaging.requestPermission();
    } catch (e) {
      _logger.w(e);
      return;
    }

    if (!kIsWeb && Platform.isAndroid) {
      messaging.subscribeToTopic("android");
    }

    FirebaseMessaging.onMessage.listen(_handleRemoteMessage);

    messaging.onTokenRefresh.listen(_handleFcmTokenRefresh);
    final token =
        await messaging.getToken(vapidKey: dotenv.env["FireBaseVapidKey"]);
    if (token == null) {
      _logger.e("fcmToken null");
    } else {
      _handleFcmTokenRefresh(token);
    }
    _handleMessageInteraction(await messaging.getInitialMessage());
  }

  _handleMessageInteraction(RemoteMessage? message) {
    if (message == null) {
      return;
    }
    if (message.data["type"] != notificationUpdateType) {
      return; //safety check
    }
    _messageIdToDisplay =
        app.Notification.fromJson(json.decode(message.data["payload"])).id;
  }

  _handleFcmTokenRefresh(String token) async {
    _fcmTokenMutex.protect(() async {
      if (fcmToken == token) {
        _logger.d("FCM token unchanged");
        return;
      }
      if (fcmToken != null) {
        try {
          await FcmTokenService.deregisterFcmToken(fcmToken!);
        } catch (e) {
          final err = "Could not deregister FCM: $e";
          _logger.e(err);
          Toast.showToastNoContext(err);
        }
      }
      fcmToken = token;

      _logger.d("firebase token: $fcmToken");
      if (fcmToken != null) {
        try {
          await FcmTokenService.registerFcmToken(fcmToken!);
          if (!kIsWeb) messaging.subscribeToTopic("announcements");
        } catch (e) {
          final err = "Could not setup FCM: $e";
          _logger.e(err);
          Toast.showToastNoContext(err);
        }
      } else {
        _logger.e("FCM token is null");
      }
    });
  }

  _handleRemoteMessage(RemoteMessage message) {
    _handleRemoteMessageCommand(message.data);
  }

  _handleRemoteMessageCommand(dynamic data) {
    switch (data["type"]) {
      case notificationUpdateType:
        final updatedNotification =
            app.Notification.fromJson(json.decode(data["payload"]));
        final idx = notifications
            .indexWhere((element) => element.id == updatedNotification.id);
        if (idx != -1) {
          notifications[idx] = updatedNotification;
        } else {
          notifications.insert(0, updatedNotification);
        }
        if (updatedNotification.isRead) {
          Eraser.clearAppNotificationsByTag(updatedNotification.id);
        }
        notifyListeners();
        break;
      case notificationDeleteManyType:
        List<dynamic> ids = json.decode(data["payload"]);
        ids.forEach((id) => Eraser.clearAppNotificationsByTag(id));
        notifications.removeWhere((element) => ids.contains(element.id));
        notifyListeners();
        break;
      case notificationReleaseInfoType:
        Future.delayed(Duration(
                seconds:
                    10 + Random().nextInt(60))) // ensure actually available and spread requests
            .then((_) => AppUpdater.updateAvailable().then((res) {
                  if (res == true) {
                    notifyListeners();
                  }
                }));
        break;
      default:
        _logger.e("Got message of unknown type: ${data["type"]}");
    }
  }

  handleQueuedMessages() async {
    await _messageMutex.acquire();

    String? read = await _storage.read(key: messageKey);
    final List list;

    if (read != null) {
      list = json.decode(read);
    } else {
      list = [];
    }

    list.map((e) => RemoteMessage.fromMap(e)).forEach(_handleRemoteMessage);
    await _storage.delete(key: messageKey);
    _messageMutex.release();
  }

  checkMessageDisplay(BuildContext context) async {
    if (_messageIdToDisplay == null) {
      return;
    }
    final idx = notifications
        .indexWhere((element) => element.id == _messageIdToDisplay);
    if (idx == -1) {
      return;
    }
    _messageIdToDisplay = null;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (ModalRoute.of(context)?.settings.name !=
          NotificationList.preferredRouteName) {
        Navigator.push(
            context,
            platformPageRoute(
                context: context,
                settings: const RouteSettings(
                    name: NotificationList.preferredRouteName),
                builder: (context) => const NotificationList()));
      }
      notifications[idx].show(context);
      notifications[idx].isRead = true;
      await updateNotifications(context, idx);
      notifyListeners();
    });
  }

  loadDeviceGroups(BuildContext context) async {
    final locked = _deviceGroupsMutex.isLocked;
    await _deviceGroupsMutex.acquire();
    if (locked) {
      return;
    }
    deviceGroups.clear();
    notifyListeners();

    try {
      deviceGroups.addAll(
          await Future.wait(await DeviceGroupsService.getDeviceGroups()));
    } catch (e) {
      final err = "Could not load device groups $e";
      _logger.e(err);
      Toast.showToastNoContext(err);
    }
    notifyListeners();

    _deviceGroupsMutex.release();
  }

  bool loadingDeviceGroups() {
    return _deviceGroupsMutex.isLocked;
  }

  loadLocations(BuildContext context) async {
    final locked = _locationsMutex.isLocked;
    await _locationsMutex.acquire();
    if (locked) {
      return;
    }
    locations.clear();
    notifyListeners();

    try {
      locations.addAll(await Future.wait(await LocationService.getLocations()));
    } catch (e) {
      final err = "Could not load locations $e";
      _logger.e(err);
      Toast.showToastNoContext(err);
    }
    notifyListeners();

    _locationsMutex.release();
  }

  bool loadingLocations() {
    return _locationsMutex.isLocked;
  }

  loadNetworks(BuildContext context) async {
    final locked = _networksMutex.isLocked;
    await _networksMutex.acquire();
    if (locked) {
      return;
    }
    networks.clear();
    notifyListeners();

    try {
      networks.addAll(await NetworksService.getNetworks());
    } catch (e) {
      final err = "Could not load networks $e";
      _logger.e(err);
      Toast.showToastNoContext(err);
    }
    _mergeDiscoveredServicesWithNetworks();
    for (final network in networks) {
      final networkDevices = devices.where((device) =>
          network.device_local_ids?.contains(device.local_id) ?? false);
      networkDevices.forEach((d) => d.network = network);
      for (final group in deviceGroups) {
        if (group.device_ids.every((String groupDeviceId) =>
            (network.device_ids ?? <String>[])
                .contains(groupDeviceId.substring(0, 57)) as bool)) {
          group.network = network;
        }
      }
    }
    await MgwDeviceManager.updateDeviceConnectionStatusFromMgw(devices);
    notifyListeners();

    _networksMutex.release();
  }

  bool loadingNetworks() {
    return _networksMutex.isLocked;
  }

  loadAspects() async {
    final locked = _aspectsMutex.isLocked;
    await _aspectsMutex.acquire();
    if (locked) {
      return aspects;
    }
    try {
      for (var element in (await AspectsService.getAspects())) {
        aspects[element.id] = element;
      }
    } catch (e) {
      final err = "Could not load aspects $e";
      _logger.e(err);
      Toast.showToastNoContext(err);
    }
    notifyListeners();
    _aspectsMutex.release();
  }

  Discovery? _discovery;

  _manageNetworkDiscovery() async {
    if (kIsWeb) return; // no mDNS in browser
    if (_discovery != null) return;
    _discovery = await startDiscovery('_snrgy._tcp', ipLookupType: IpLookupType.any);
    _discovery!.addListener(_mergeDiscoveredServicesWithNetworks);
  }

  _mergeDiscoveredServicesWithNetworks() {
    // TODO get serial ID from the mDNS response or try to query it from device connector deployment which should return the hub id in the future
    networks.forEach((n) => n.localService = null);
    _discovery?.services.forEach((service) {
      final nI = networks.indexWhere((n) =>
          n.id ==
          utf8.decode((service.txt?["serial"] ?? Uint8List(0))
              .map((e) => e.toInt())
              .toList()));
      if (nI != -1) {
        networks[nI].localService = service;
      }
    });
  }

  loadStoredMGWs() async {
    _logger.d("App State: Load stored mgw");
    await _gatewaysMutex.acquire();
    var storedMGWs = await MgwStorage.LoadPairedMGWs();
    gateways.clear();
    gateways.addAll(storedMGWs);
    // TODO: REfresh host names and ip adresses
    _gatewaysMutex.release();
    notifyListeners();
  }

  onLogout() async {
    try {
      await messaging.deleteToken();
    } catch (e) {
      _logger.w("Could not delete FCM token: $e");
    }
    fcmToken = null;
    await _storage.delete(key: messageKey);
    _initialized = false;
    deviceClasses.clear();

    deviceTypesPermSearch.clear();
    deviceTypes.clear();

    nestedFunctions.clear();
    _deviceSearchFilter = DeviceSearchFilter.empty();
    totalDevices = 0;

    devices.clear();
    _allDevicesLoaded = false;
    _deviceOffset = 0;

    deviceGroups.clear();

    locations.clear();

    networks.clear();

    aspects.clear();

    concepts.clear();

    characteristics.clear();

    notifications.clear();
    _notificationInited = false;
    _messageIdToDisplay = null;
    CacheHelper.clearCache();
  }

  @override
  // ignore: unnecessary_overrides
  void notifyListeners() {
    super.notifyListeners();
  }

  final StreamController _refreshPressedController = StreamController();
  Stream? _refreshPressedControllerStream;

  Stream get refreshPressed {
    if (_refreshPressedControllerStream != null) {
      return _refreshPressedControllerStream!;
    }
    _refreshPressedControllerStream =
        _refreshPressedController.stream.asBroadcastStream();
    return _refreshPressedControllerStream!;
  }

  void pushRefresh() => _refreshPressedController.add(null);

  List<bool> setAndGetDisabledTabs() {
    final state = AppState();
    final List<bool> disabledList =
    List.generate(navItems.length, (index) => true);
    navItems.forEach((navItem) {
      switch (navItem.index) {
        case tabLocations:
          navItem.disabled =
              state.locations.isEmpty && !LocationService.isListAvailable();
          break;
        case tabGroups:
          navItem.disabled = state.deviceGroups.isEmpty &&
              !DeviceGroupsService.isListAvailable();
          break;
        case tabNetworks:
          navItem.disabled =
              state.networks.isEmpty && !NetworksService.isAvailable();
          break;
        case tabClasses:
          navItem.disabled = state.deviceClasses.isEmpty &&
              !DeviceClassesService.isAvailable();
          break;
        case tabSmartServices:
          navItem.disabled = !SmartServiceService.isAvailable();
          break;
        case tabDashboard:
          navItem.disabled = !SmartServiceService.isAvailable();
        default:
          navItem.disabled = false;
      }
      disabledList[navItem.index] = navItem.disabled;
    });
    return disabledList;
  }
}
