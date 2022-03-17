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
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/exceptions/no_network_exception.dart';
import 'package:mobile_app/models/function.dart';
import 'package:mobile_app/models/notification.dart' as app;
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/device_classes.dart';
import 'package:mobile_app/services/device_commands.dart';
import 'package:mobile_app/services/device_types.dart';
import 'package:mobile_app/services/device_types_perm_search.dart';
import 'package:mobile_app/services/devices.dart';
import 'package:mobile_app/services/fcm_token.dart';
import 'package:mobile_app/services/functions.dart';
import 'package:mobile_app/services/notifications.dart';
import 'package:mobile_app/util/get_broadcast_channel.dart';
import 'package:mobile_app/util/remote_message_encoder.dart';
import 'package:mutex/mutex.dart';

import 'models/device_class.dart';
import 'models/device_command_response.dart';
import 'models/device_instance.dart';
import 'models/device_type.dart';
import 'widgets/toast.dart';

const notificationUpdateType = "put notification";
const notificationDeleteManyType = "delete notifications";
const messageKey = "messages";

class AppState extends ChangeNotifier {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  static const storage = FlutterSecureStorage();

  static final _messageMutex = Mutex();
  static queueRemoteMessage(RemoteMessage message) async {
    await _messageMutex.acquire();
    _logger.d("Queuing message " + message.messageId.toString());

    String? read = await storage.read(key: messageKey);
    final List list;

    if (read != null) {
      list = json.decode(read);
    } else {
      list = [];
    }

    list.add(remoteMessageToMap(message));

    await storage.write(key: messageKey, value: json.encode(list));
    _messageMutex.release();
  }

  FirebaseMessaging messaging = FirebaseMessaging.instance;
  String? fcmToken;

  bool _initialized = false;

  final Map<String, DeviceClass> deviceClasses = {};
  final Mutex _deviceClassesMutex = Mutex();

  final Map<String, DeviceTypePermSearch> deviceTypesPermSearch = {};
  final Mutex _deviceTypesPermSearchMutex = Mutex();

  final Map<String, DeviceType> deviceTypes = {};

  final Map<String, NestedFunction> nestedFunctions = {};
  final Mutex _nestedFunctionsMutex = Mutex();

  String _deviceSearchText = '';

  int totalDevices = -1;
  final Mutex _totalDevicesMutex = Mutex();

  final List<DeviceInstance> devices = <DeviceInstance>[];
  final Mutex _devicesMutex = Mutex();

  int _deviceClassArrIndex = 0;
  int _classOffset = 0;

  List<app.Notification> notifications = [];
  final Mutex _notificationsMutex = Mutex();
  bool _notificationInited = false;
  String? _messageIdToDisplay;

  bool loggedIn() => Auth.tokenValid();

  bool loggingIn() => Auth.loggingIn();

  AppState() {
    SystemChannels.lifecycle.setMessageHandler((msg) {
      if (msg == AppLifecycleState.resumed.toString()) {
        handleQueuedMessages();
      }
      return Future.value(null);
    });
    if (kIsWeb) { // receive broadcasts from service worker
      getBroadcastChannel("optimise-mobile-app").onMessage.listen((event) {
        _handleRemoteMessageCommand(event.data["data"]);
      });
    }
  }

  init(BuildContext context) async {
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageInteraction);
    await loadDeviceClasses(context);
    await loadDeviceTypes(context);
    await loadNestedFunctions(context);
    await initMessaging();
    _initialized = true;
  }

  loadDeviceClasses(BuildContext context) async {
    final locked = _deviceClassesMutex.isLocked;
    _deviceClassesMutex.acquire();
    if (locked) {
      return deviceClasses;
    }
    for (var element in (await DeviceClassesService.getDeviceClasses(context, this))) {
      deviceClasses[element.id] = element;
    }
    notifyListeners();
    _deviceClassesMutex.release();
  }

  loadDeviceTypes(BuildContext context) async {
    final locked = _deviceTypesPermSearchMutex.isLocked;
    _deviceTypesPermSearchMutex.acquire();
    if (locked) {
      return deviceTypesPermSearch;
    }
    for (var element in (await DeviceTypesPermSearchService.getDeviceTypes(context, this))) {
      deviceTypesPermSearch[element.id] = element;
    }
    notifyListeners();
    _deviceTypesPermSearchMutex.release();
  }

  loadNestedFunctions(BuildContext context) async {
    final locked = _nestedFunctionsMutex.isLocked;
    _nestedFunctionsMutex.acquire();
    if (locked) {
      return nestedFunctions;
    }
    for (var element in (await FunctionsService.getNestedFunctions(context, this))) {
      nestedFunctions[element.id] = element;
    }
    notifyListeners();
    _nestedFunctionsMutex.release();
  }

  updateTotalDevices(BuildContext context) async {
    _totalDevicesMutex.acquire();
    final total = await DevicesService.getTotalDevices(context, this, _deviceSearchText);
    if (total != totalDevices) {
      totalDevices = total;
      notifyListeners();
    }
  }

  searchDevices(String query, BuildContext context, [bool force = false]) async {
    if (!force && query == _deviceSearchText) {
      return;
    }
    _deviceClassArrIndex = 0;
    _classOffset = 0;
    if (devices.isNotEmpty) {
      devices.clear();
      notifyListeners();
    }
    _deviceSearchText = query;
    updateTotalDevices(context);
    loadDevices(context);
  }

  refreshDevices(BuildContext context) async {
    await searchDevices(_deviceSearchText, context, true);
  }

  loadDevices(BuildContext context, [int size = 50, bool skipMutex = false]) async {
    if (!skipMutex && _devicesMutex.isLocked) {
      return;
    }
    if (!skipMutex) _devicesMutex.acquire();

    if (!_initialized) {
      await init(context);
    }

    late final List<DeviceInstance> newDevices;
    try {
      List<String> deviceTypeIds = deviceTypesPermSearch.values
          .where((element) => element.device_class_id == deviceClasses.keys.elementAt(_deviceClassArrIndex))
          .map((e) => e.id)
          .toList(growable: false);

      newDevices = await DevicesService.getDevices(context, this, size, _classOffset, _deviceSearchText, deviceTypeIds);
    } catch (e) {
      _logger.e("Could not get devices: " + e.toString());
      Toast.showErrorToast(context, "Could not load devices");
      if (!skipMutex) _devicesMutex.release();
      return;
    }
    devices.addAll(newDevices);
    _classOffset += newDevices.length;
    if (newDevices.isNotEmpty) {
      notifyListeners();
      loadOnOffStates(context, newDevices); // no await => run in background
    }
    if (totalDevices < devices.length) {
      await updateTotalDevices(context); // when loadDevices called directly
    }
    if (newDevices.length < size && deviceClasses.length - 1 > _deviceClassArrIndex) {
      _classOffset = 0;
      _deviceClassArrIndex++;
      loadDevices(context, size - newDevices.length, true);
    }
    if (!skipMutex) _devicesMutex.release();
  }

  loadDeviceType(BuildContext context, String id, [bool force = false]) async {
    if (!force && deviceTypes.containsKey(id)) {
      return;
    }
    final t = await DeviceTypesService.getDeviceType(context, this, id);
    if (t == null) {
      return;
    }
    deviceTypes[id] = t;
  }

  loadOnOffStates(BuildContext context, List<DeviceInstance> devices) async {
    await loadStates(context, devices, [dotenv.env['FUNCTION_GET_ON_OFF_STATE'] ?? '']);
  }

  loadStates(BuildContext context, List<DeviceInstance> devices, [List<String>? limitToFunctionIds]) async {
    final List<CommandCallback> commandCallbacks = [];
    for (var element in devices) {
      await loadDeviceType(context, element.device_type_id);
      element.prepareStates(deviceTypes[element.device_type_id]!);
      commandCallbacks.addAll(element.getStateFillFunctions(limitToFunctionIds));
    }
    if (commandCallbacks.isEmpty) {
      return;
    }
    final List<DeviceCommandResponse> result;
    try {
      result = await DeviceCommandsService.runCommands(context, this, commandCallbacks.map((e) => e.command).toList(growable: false));
    } on NoNetworkException {
      _logger.e("failed to loadAllStates: currently offline");
      rethrow;
    } catch (e) {
      _logger.e("failed to loadAllStates: " + e.toString());
      rethrow;
    }
    assert(result.length == commandCallbacks.length);
    for (var i = 0; i < commandCallbacks.length; i++) {
      if (result[i].status_code == 200) {
        commandCallbacks[i].callback(result[i].message);
      } else {
        _logger.e(result[i].status_code.toString() + ": " + result[i].message);
      }
    }
    notifyListeners();
  }

  loadNotifications(BuildContext? context) async {
    final locked = _notificationsMutex.isLocked;
    _notificationsMutex.acquire();
    if (locked) {
      return notifications;
    }
    notifications.clear();
    await storage.delete(key: messageKey); // clean up any queued messages of previous instances

    const limit = 10000;
    int offset = 0;
    app.NotificationResponse? response;
    do {
      response = await NotificationsService.getNotifications(context, this, limit, offset);
      final tmp = response?.notifications.reversed.toList() ?? []; // got reverse ordered batches form api
      tmp.addAll(notifications);
      notifications = tmp;
      offset += response?.notifications.length ?? 0;
      notifyListeners();
    } while (response != null && response.notifications.length == limit);
    _notificationsMutex.release();
  }

  updateNotifications(BuildContext context, int index) async {
    await NotificationsService.setNotification(context, this, notifications[index]);
    notifyListeners();
  }

  deleteNotification(BuildContext context, int index) async {
    try {
      await NotificationsService.deleteNotifications(context, this, [notifications[index].id]);
    } catch (e) {
      _logger.e(e.toString());
      Toast.showErrorToast(context, "Could not delete notification");
    }
    // notifications.removeAt(index);
    // notifyListeners(); Expect change propagation through FCM
  }

  deleteAllNotifications(BuildContext context) async {
    try {
      await NotificationsService.deleteNotifications(context, this, notifications.map((e) => e.id).toList(growable: false));
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
    fcmToken = await messaging.getToken(vapidKey: dotenv.env["FireBaseVapidKey"]);
    _handleFcmTokenRefresh(null);
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

  _handleFcmTokenRefresh(String? oldToken) async {
    if (oldToken != null) {
      try {
        await FcmTokenService.deregisterFcmToken(oldToken);
      } catch (e) {
        _logger.e("Could not deregister FCM: " + e.toString());
      }
    }

    _logger.d("firebase token: " + fcmToken.toString());
    if (fcmToken != null) {
      try {
        await FcmTokenService.registerFcmToken(fcmToken!);
        messaging.subscribeToTopic("announcements");
      } catch (e) {
        _logger.e("Could not setup FCM: " + e.toString());
      }
    } else {
      _logger.e("FCM token is null");
    }
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
        notifyListeners();
        break;
      case notificationDeleteManyType:
        List<dynamic> ids = json.decode(data["payload"]);
        notifications.removeWhere((element) => ids.contains(element.id));
        notifyListeners();
        break;
      default:
        _logger.e("Got message of unknown type: " + data["type"]);
    }
  }

  handleQueuedMessages() async {
    await _messageMutex.acquire();

    String? read = await storage.read(key: messageKey);
    final List list;

    if (read != null) {
      list = json.decode(read);
    } else {
      list = [];
    }

    list.map((e) => RemoteMessage.fromMap(e)).forEach(_handleRemoteMessage);
    await storage.delete(key: messageKey);
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

  @override
  void notifyListeners() {
    _logger.d("notifying listeners");
    super.notifyListeners();
  }
}
