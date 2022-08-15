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

import 'dart:convert';

import 'package:eraser/eraser.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/exceptions/no_network_exception.dart';
import 'package:mobile_app/models/aspect.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/function.dart';
import 'package:mobile_app/models/location.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/models/notification.dart' as app;
import 'package:mobile_app/services/aspects.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/device_classes.dart';
import 'package:mobile_app/services/device_commands.dart';
import 'package:mobile_app/services/device_groups.dart';
import 'package:mobile_app/services/device_types.dart';
import 'package:mobile_app/services/device_types_perm_search.dart';
import 'package:mobile_app/services/devices.dart';
import 'package:mobile_app/services/fcm_token.dart';
import 'package:mobile_app/services/functions.dart';
import 'package:mobile_app/services/locations.dart';
import 'package:mobile_app/services/networks.dart';
import 'package:mobile_app/services/notifications.dart';
import 'package:mobile_app/shared/get_broadcast_channel.dart';
import 'package:mobile_app/shared/remote_message_encoder.dart';
import 'package:mobile_app/widgets/shared/toast.dart';
import 'package:mutex/mutex.dart';

import 'models/device_class.dart';
import 'models/device_command_response.dart';
import 'models/device_instance.dart';
import 'models/device_search_filter.dart';
import 'models/device_type.dart';

const notificationUpdateType = "put notification";
const notificationDeleteManyType = "delete notifications";
const messageKey = "messages";

class AppState extends ChangeNotifier with WidgetsBindingObserver {
  static final _instance = AppState._internal();
  factory AppState() => _instance;
  AppState._internal() {
    WidgetsBinding.instance?.addObserver(this);
    if (kIsWeb) {
      // receive broadcasts from service worker
      getBroadcastChannel("optimise-mobile-app").onMessage.listen((event) {
        _handleRemoteMessageCommand(event.data["data"]);
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      handleQueuedMessages();
    }
  }

  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  static const _storage = FlutterSecureStorage();

  static final _messageMutex = Mutex();

  static queueRemoteMessage(RemoteMessage message) async {
    await _messageMutex.acquire();
    _logger.d("Queuing message " + message.messageId.toString());
    final remoteMessageMap = remoteMessageToMap(message);

    switch (remoteMessageMap["data"]["type"]) {
      case notificationUpdateType:
        final updatedNotification = app.Notification.fromJson(json.decode(remoteMessageMap["data"]["payload"]));
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

  final Map<String, Aspect> aspects = {};
  final Mutex _aspectsMutex = Mutex();

  List<app.Notification> notifications = [];
  final Mutex _notificationsMutex = Mutex();
  bool _notificationInited = false;
  String? _messageIdToDisplay;

  bool get loggedIn => Auth().loggedIn;

  bool get loggingIn => Auth().loggingIn;

  init(BuildContext context) async {
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageInteraction);
    await loadDeviceClasses(context);
    await loadDeviceTypes(context);
    await loadNestedFunctions(context);
    await loadAspects(context);
    await initMessaging();
    _initialized = true;
  }

  loadDeviceClasses(BuildContext context) async {
    final locked = _deviceClassesMutex.isLocked;
    await _deviceClassesMutex.acquire();
    if (locked) {
      return deviceClasses;
    }
    deviceClasses.clear();
    notifyListeners();
    for (var element in (await DeviceClassesService.getDeviceClasses())) {
      deviceClasses[element.id] = element;
    }
    notifyListeners();
    _deviceClassesMutex.release();
  }

  bool get loadingDeviceClasses {
    return _deviceClassesMutex.isLocked;
  }

  loadDeviceTypes(BuildContext context) async {
    final locked = _deviceTypesPermSearchMutex.isLocked;
    await _deviceTypesPermSearchMutex.acquire();
    if (locked) {
      return deviceTypesPermSearch;
    }
    for (var element in (await DeviceTypesPermSearchService.getDeviceTypes())) {
      deviceTypesPermSearch[element.id] = element;
    }
    notifyListeners();
    _deviceTypesPermSearchMutex.release();
  }

  loadNestedFunctions(BuildContext context) async {
    final locked = _nestedFunctionsMutex.isLocked;
    await _nestedFunctionsMutex.acquire();
    if (locked) {
      return nestedFunctions;
    }
    for (var element in (await FunctionsService.getNestedFunctions())) {
      nestedFunctions[element.id] = element;
    }
    notifyListeners();
    _nestedFunctionsMutex.release();
  }

  updateTotalDevices(BuildContext context) async {
    await _totalDevicesMutex.protect(() async {
      final total = await DevicesService.getTotalDevices(_deviceSearchFilter);
      if (total != totalDevices) {
        totalDevices = total;
        notifyListeners();
      }
    });
  }

  Future searchDevices(DeviceSearchFilter filter, BuildContext context, [bool force = false]) async {
    if (!force && _deviceSearchFilter == filter) {
      return;
    }
    _allDevicesLoaded = false;
    if (devices.isNotEmpty) {
      devices.clear();
    }
    notifyListeners();
    _deviceSearchFilter = filter.clone();
    _deviceOffset = 0;
    await updateTotalDevices(context);
    await loadDevices(context);
  }

  refreshDevices(BuildContext context) async {
    await searchDevices(_deviceSearchFilter, context, true);
  }

  loadDevices(BuildContext context, [int? offset]) async {
    if (_allDevicesLoaded) {
      return;
    }
    await _devicesMutex.acquire();

    if (_allDevicesLoaded || (offset != null && offset < devices.length)) {
      _devicesMutex.release();
      notifyListeners(); // missing loadingDevices() change otherwise
      return;
    }

    if (!_initialized) {
      await init(context);
    }

    late final List<DeviceInstance> newDevices;
    const limit = 50;
    try {
      newDevices = await DevicesService.getDevices(limit, _deviceOffset, _deviceSearchFilter);
    } catch (e) {
      _logger.e("Could not get devices: " + e.toString());
      Toast.showErrorToast(context, "Could not load devices");
      notifyListeners(); // missing loadingDevices() change otherwise
      _devicesMutex.release();
      return;
    }
    devices.addAll(newDevices);
    _allDevicesLoaded = newDevices.length < limit;
    _deviceOffset += newDevices.length;
    if (newDevices.isNotEmpty) {
      await loadStates(context, newDevices, [], [dotenv.env['FUNCTION_GET_ON_OFF_STATE'] ?? '']);
    }
    if (totalDevices <= _deviceOffset) {
      await updateTotalDevices(context); // when loadDevices called directly
    }
    _devicesMutex.release();
    notifyListeners();
  }

  bool get loadingDevices {
    return _totalDevicesMutex.isLocked || _devicesMutex.isLocked;
  }

  bool get allDevicesLoaded {
    return _allDevicesLoaded;
  }

  loadDeviceType(BuildContext context, String id, [bool force = false]) async {
    if (!force && deviceTypes.containsKey(id)) {
      return;
    }
    final t = await DeviceTypesService.getDeviceType(id);
    if (t == null) {
      return;
    }
    deviceTypes[id] = t;
  }

  loadStates(BuildContext context, List<DeviceInstance> devices, List<DeviceGroup> groups, [List<String>? limitToFunctionIds]) async {
    final List<CommandCallback> commandCallbacks = [];
    for (var element in devices) {
      await loadDeviceType(context, element.device_type_id);
      element.prepareStates(deviceTypes[element.device_type_id]!);
      final callbacks = element.getStateFillFunctions(limitToFunctionIds);
      if (element.getConnectionStatus() == DeviceConnectionStatus.offline) {
        callbacks.forEach((element) => element.callback(null));
      } else {
        commandCallbacks.addAll(callbacks);
      }
    }
    for (var element in groups) {
      element.prepareStates();
      commandCallbacks.addAll(element.getStateFillFunctions(limitToFunctionIds));
    }
    if (commandCallbacks.isEmpty) {
      notifyListeners();
      return;
    }
    List<DeviceCommandResponse> result;
    try {
      result = await DeviceCommandsService.runCommands(commandCallbacks.map((e) => e.command).toList(growable: false));
    } on NoNetworkException {
      _logger.e("failed to loadStates: currently offline");
      result = [];
      for (var _ in commandCallbacks) {
        result.add(DeviceCommandResponse(200, null));
      }
    } catch (e) {
      _logger.e("failed to loadStates: " + e.toString());
      result = [];
      for (var _ in commandCallbacks) {
        result.add(DeviceCommandResponse(200, null));
      }
    }
    assert(result.length == commandCallbacks.length);
    for (var i = 0; i < commandCallbacks.length; i++) {
      if (result[i].status_code == 200) {
        commandCallbacks[i].callback(result[i].message);
      } else {
        _logger.e(result[i].status_code.toString() + ": " + result[i].message);
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
    await _storage.delete(key: messageKey); // clean up any queued messages of previous instances

    const limit = 10000;
    int offset = 0;
    app.NotificationResponse? response;
    try {
      do {
        try {
          response = await NotificationsService.getNotifications(limit, offset);
        } catch (e) {
          _logger.e("Could not load notifications: " + e.toString());
          return;
        }
        final tmp = response?.notifications.reversed.toList() ?? []; // got reverse ordered batches form api
        tmp.addAll(notifications);
        notifications = tmp;
        offset += response?.notifications.length ?? 0;
        notifyListeners();
      } while (response != null && response.notifications.length == limit);
    } catch (e) {
      const err = "Could not load notifications";
      if (context != null) Toast.showErrorToast(context, err);
      _logger.e(err + ": " + e.toString());
    } finally {
      _notificationsMutex.release();
    }
  }

  updateNotifications(BuildContext context, int index) async {
    await NotificationsService.setNotification(notifications[index]);
    notifyListeners();
  }

  deleteNotification(BuildContext context, int index) async {
    try {
      await NotificationsService.deleteNotifications([notifications[index].id]);
    } catch (e) {
      _logger.e(e.toString());
      Toast.showErrorToast(context, "Could not delete notification");
    }
    // notifications.removeAt(index);
    // notifyListeners(); Expect change propagation through FCM
  }

  deleteAllNotifications(BuildContext context) async {
    try {
      await NotificationsService.deleteNotifications(notifications.map((e) => e.id).toList(growable: false));
    } catch (e) {
      _logger.e(e.toString());
      Toast.showErrorToast(context, "Could not delete notifications");
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
    await messaging.requestPermission();

    FirebaseMessaging.onMessage.listen(_handleRemoteMessage);

    messaging.onTokenRefresh.listen(_handleFcmTokenRefresh);
    final token = await messaging.getToken(vapidKey: dotenv.env["FireBaseVapidKey"]);
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
    _messageIdToDisplay = app.Notification.fromJson(json.decode(message.data["payload"])).id;
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
          _logger.e("Could not deregister FCM: " + e.toString());
        }
      }
      fcmToken = token;

      _logger.d("firebase token: " + fcmToken.toString());
      if (fcmToken != null) {
        try {
          await FcmTokenService.registerFcmToken(fcmToken!);
          if (!kIsWeb) messaging.subscribeToTopic("announcements");
        } catch (e) {
          _logger.e("Could not setup FCM: " + e.toString());
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
        final updatedNotification = app.Notification.fromJson(json.decode(data["payload"]));
        final idx = notifications.indexWhere((element) => element.id == updatedNotification.id);
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
      default:
        _logger.e("Got message of unknown type: " + data["type"]);
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
    final idx = notifications.indexWhere((element) => element.id == _messageIdToDisplay);
    if (idx == -1) {
      return;
    }
    _messageIdToDisplay = null;
    notifications[idx].show(context);
    notifications[idx].isRead = true;
    await updateNotifications(context, idx);
    notifyListeners();
  }

  loadDeviceGroups(BuildContext context) async {
    final locked = _deviceGroupsMutex.isLocked;
    await _deviceGroupsMutex.acquire();
    if (locked) {
      return;
    }
    deviceGroups.clear();
    notifyListeners();

    deviceGroups.addAll(await Future.wait(await DeviceGroupsService.getDeviceGroups()));
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

    locations.addAll(await Future.wait(await LocationService.getLocations()));
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

    networks.addAll(await NetworksService.getNetworks());
    notifyListeners();

    _networksMutex.release();
  }

  bool loadingNetworks() {
    return _networksMutex.isLocked;
  }

  loadAspects(BuildContext context) async {
    final locked = _aspectsMutex.isLocked;
    await _aspectsMutex.acquire();
    if (locked) {
      return aspects;
    }
    for (var element in (await AspectsService.getAspects())) {
      aspects[element.id] = element;
    }
    notifyListeners();
    _aspectsMutex.release();
  }

  onLogout() async {
    try {
      await messaging.deleteToken();
    } catch (e) {
      _logger.w("Could not delete FCM token: " + e.toString());
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

    notifications.clear();
    _notificationInited = false;
    _messageIdToDisplay = null;
  }

  @override
  void notifyListeners() {
    super.notifyListeners();
  }
}
