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
import 'dart:io';
import 'dart:math';

import 'package:eraser/eraser.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/models/notification.dart' as app;
import 'package:mobile_app/services/app_update.dart';
import 'package:mobile_app/services/fcm_token.dart';
import 'package:mobile_app/services/notifications.dart';
import 'package:mobile_app/shared/remote_message_encoder.dart';
import 'package:mobile_app/widgets/notifications/notification_list.dart';
import 'package:mobile_app/widgets/shared/toast.dart';
import 'package:mutex/mutex.dart';

const notificationUpdateType = 'put notification';
const notificationDeleteManyType = 'delete notifications';
const notificationReleaseInfoType = 'release_info';
const messageKey = 'messages';

mixin NotificationMixin on ChangeNotifier {
  static final _logger = Logger(printer: SimplePrinter());

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
  );
  static final _messageMutex = Mutex();
  final _fcmTokenMutex = Mutex();
  final _notificationsMutex = Mutex();

  List<app.Notification> notifications = [];
  bool _notificationInited = false;
  String? _messageIdToDisplay;

  FirebaseMessaging messaging = FirebaseMessaging.instance;
  String? fcmToken;

  static Future<void> queueRemoteMessage(RemoteMessage message) async {
    await _messageMutex.acquire();
    _logger.d('Queuing message ${message.messageId}');
    final map = remoteMessageToMap(message);

    switch (map['data']['type']) {
      case notificationUpdateType:
        final n = app.Notification.fromJson(json.decode(map['data']['payload']));
        if (n.isRead) await Eraser.clearAppNotificationsByTag(n.id);
        break;
      case notificationDeleteManyType:
        final ids = json.decode(map['data']['payload']) as List<dynamic>;
        for (final id in ids) {
          await Eraser.clearAppNotificationsByTag(id as String);
        }
        break;
    }

    final read = await _storage.read(key: messageKey);
    final list = read != null ? json.decode(read) as List : [];
    list.add(map);
    await _storage.write(key: messageKey, value: json.encode(list));
    _messageMutex.release();
  }

  Future<void> initMessaging() async {
    _logger.d('init Messaging');
    try {
      await messaging.requestPermission();
    } catch (e) {
      _logger.w(e);
      return;
    }
    if (!kIsWeb && Platform.isAndroid) {
      await messaging.subscribeToTopic('android');
    }
    FirebaseMessaging.onMessage.listen(_handleRemoteMessage);
    messaging.onTokenRefresh.listen(_handleFcmTokenRefresh);

    if (!kIsWeb && Platform.isIOS) {
      await messaging.getAPNSToken(); // must be called before getToken on iOS
    }
    final token = await messaging.getToken(
      vapidKey: dotenv.env['FireBaseVapidKey'],
    );
    if (token == null) {
      _logger.e('fcmToken null');
    } else {
      await _handleFcmTokenRefresh(token);
    }
    _logger.d('init Messaging done');
    _handleMessageInteraction(await messaging.getInitialMessage());
  }

  bool get loadingNotifications => _notificationsMutex.isLocked;

  void initNotifications(BuildContext context) {
    if (_notificationInited) return;
    _notificationInited = true;
    loadNotifications(context);
  }

  Future<void> loadNotifications(BuildContext? context) async {
    final locked = _notificationsMutex.isLocked;
    await _notificationsMutex.acquire();
    if (locked) return;
    notifications.clear();
    await _storage.delete(key: messageKey);

    const limit = 10000;
    int offset = 0;
    app.NotificationResponse? response;
    try {
      do {
        try {
          response = await NotificationsService.getNotifications(limit, offset);
        } catch (e) {
          final err = 'Could not load notifications: $e';
          _logger.e(err);
          Toast.showToastNoContext(err);
          return;
        }
        final batch = response?.notifications.reversed.toList() ?? [];
        batch.addAll(notifications);
        notifications = batch;
        offset += response?.notifications.length ?? 0;
        notifyListeners();
      } while (response != null && response.notifications.length == limit);
    } catch (e) {
      const err = 'Could not load notifications';
      _logger.e('$err: $e');
      if (context != null) Toast.showToastNoContext(err);
    } finally {
      _notificationsMutex.release();
    }
  }

  Future<void> updateNotifications(BuildContext context, int index) async {
    try {
      await NotificationsService.setNotification(notifications[index]);
    } catch (e) {
      final err = 'Could not update notification: $e';
      _logger.e(err);
      Toast.showToastNoContext(err);
    }
    notifyListeners();
  }

  Future<void> deleteNotifications(List<String> ids) async {
    try {
      await NotificationsService.deleteNotifications(ids);
    } catch (e) {
      _logger.e(e.toString());
      Toast.showToastNoContext('Could not delete notifications');
    }
  }

  Future<void> deleteAllNotifications() async {
    await deleteNotifications(
      notifications.map((e) => e.id).toList(growable: false),
    );
  }

  Future<void> checkMessageDisplay(BuildContext context) async {
    if (_messageIdToDisplay == null) return;
    final idx = notifications.indexWhere((e) => e.id == _messageIdToDisplay);
    if (idx == -1) return;
    _messageIdToDisplay = null;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (ModalRoute.of(context)?.settings.name !=
          NotificationList.preferredRouteName) {
        Navigator.push(
          context,
          platformPageRoute(
            context: context,
            settings: const RouteSettings(
              name: NotificationList.preferredRouteName,
            ),
            builder: (_) => const NotificationList(),
          ),
        );
      }
      notifications[idx].show(context);
      notifications[idx].isRead = true;
      await updateNotifications(context, idx);
      notifyListeners();
    });
  }

  Future<void> handleQueuedMessages() async {
    await _messageMutex.acquire();
    final read = await _storage.read(key: messageKey);
    final list = read != null ? json.decode(read) as List : [];
    list.map((e) => RemoteMessage.fromMap(e as Map<String, dynamic>))
        .forEach(_handleRemoteMessage);
    await _storage.delete(key: messageKey);
    _messageMutex.release();
  }

  void _handleRemoteMessage(RemoteMessage message) =>
      _handleRemoteMessageCommand(message.data);

  void _handleRemoteMessageCommand(dynamic data) {
    switch (data['type']) {
      case notificationUpdateType:
        final updated =
        app.Notification.fromJson(json.decode(data['payload'] as String));
        final idx = notifications.indexWhere((e) => e.id == updated.id);
        if (idx != -1) {
          notifications[idx] = updated;
        } else {
          notifications.insert(0, updated);
        }
        if (updated.isRead) Eraser.clearAppNotificationsByTag(updated.id);
        notifyListeners();
        break;

      case notificationDeleteManyType:
        final ids = json.decode(data['payload'] as String) as List<dynamic>;
        for (final id in ids) {
          Eraser.clearAppNotificationsByTag(id as String);
        }
        notifications.removeWhere((e) => ids.contains(e.id));
        notifyListeners();
        break;

      case notificationReleaseInfoType:
        Future.delayed(Duration(seconds: 10 + Random().nextInt(60)))
            .then((_) => AppUpdater.updateAvailable().then((res) {
          if (res == true) notifyListeners();
        }));
        break;

      default:
        _logger.e("Got message of unknown type: ${data['type']}");
    }
  }

  void _handleMessageInteraction(RemoteMessage? message) {
    if (message == null) return;
    if (message.data['type'] != notificationUpdateType) return;
    _messageIdToDisplay =
        app.Notification.fromJson(json.decode(message.data['payload'] as String)).id;
  }

  Future<void> _handleFcmTokenRefresh(String token) async {
    await _fcmTokenMutex.protect(() async {
      if (fcmToken == token) {
        _logger.d('FCM token unchanged');
        return;
      }
      if (fcmToken != null) {
        try {
          await FcmTokenService.deregisterFcmToken(fcmToken!);
        } catch (e) {
          final err = 'Could not deregister FCM: $e';
          _logger.e(err);
          Toast.showToastNoContext(err);
        }
      }
      fcmToken = token;
      _logger.d('Firebase token: $fcmToken');
      try {
        await FcmTokenService.registerFcmToken(fcmToken!);
        if (!kIsWeb) await messaging.subscribeToTopic('announcements');
      } catch (e) {
        final err = 'Could not setup FCM: $e';
        _logger.e(err);
        Toast.showToastNoContext(err);
      }
    });
  }

  Future<void> clearNotificationData() async {
    try {
      await messaging.deleteToken();
    } catch (e) {
      _logger.w('Could not delete FCM token: $e');
    }
    fcmToken = null;
    await _storage.delete(key: messageKey);
    notifications.clear();
    _notificationInited = false;
    _messageIdToDisplay = null;
  }
}