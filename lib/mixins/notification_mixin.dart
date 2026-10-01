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
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:eraser/eraser.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/shared/account_epoch.dart';
import 'package:mobile_app/models/notification.dart' as app;
import 'package:mobile_app/services/app_update.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/fcm_token.dart';
import 'package:mobile_app/services/notifications.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/remote_message_encoder.dart';
import 'package:mobile_app/widgets/notifications/notification_list.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mutex/mutex.dart';

const notificationUpdateType = 'put notification';
const notificationDeleteManyType = 'delete notifications';
const notificationReleaseInfoType = 'release_info';
const messageKey = 'messages';
const releaseTopic = 'android';
const preReleaseTopic = 'android-prerelease';

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

  /// Resolved on use, not as a field: a field initializer runs while AppState is
  /// being constructed, and FirebaseMessaging.instance throws until
  /// Firebase.initializeApp has completed - which AppInitializer.runDeferred
  /// does without being awaited, so the widget tree can get there first.
  FirebaseMessaging get messaging =>
      messagingOverride ?? FirebaseMessaging.instance;

  /// Replaces [FirebaseMessaging.instance], which needs a Firebase app.
  @visibleForTesting
  FirebaseMessaging? messagingOverride;

  String? fcmToken;

  /// The token the backend has registered for the signed-in account, or null.
  String? _registeredFcmToken;

  /// The deletions of previous accounts' tokens, each chained onto the one
  /// before. Awaited before a token is requested again, which would otherwise
  /// return a token about to be deleted.
  Future<void> _fcmTokenDeletions = Future.value();
  int _fcmTokenDeletionsQueued = 0;

  /// How long a token request waits for the deletions.
  @visibleForTesting
  Duration fcmTokenDeletionTimeout = const Duration(seconds: 10);

  /// Completes when the deletions queued so far have ended.
  @visibleForTesting
  Future<void> get fcmTokenDeletionsForTest => _fcmTokenDeletions;

  StreamSubscription<RemoteMessage>? _messageSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;

  /// Every Android install hears about stable releases; prerelease notices go
  /// to their own topic, which follows the pre-release setting.
  Future<void> syncReleaseTopics() async {
    if (!releaseTopicsSupported()) {
      return;
    }
    try {
      await messaging.subscribeToTopic(releaseTopic);
      if (Settings.getPreReleaseMode()) {
        await messaging.subscribeToTopic(preReleaseTopic);
      } else {
        await messaging.unsubscribeFromTopic(preReleaseTopic);
      }
    } catch (e, s) {
      ErrorReporter.log('Could not update release topics', e, s);
    }
  }

  /// Release topics exist for Android only.
  @visibleForTesting
  static bool Function() releaseTopicsSupported = () => Platform.isAndroid;

  static Future<void> queueRemoteMessage(RemoteMessage message) async {
    await _messageMutex.acquire();
    // Everything after the acquire is inside the try: the payload is decoded
    // here, and a malformed one throws. This runs in the background isolate
    // that FCM reuses, so a lock left behind blocks every later message
    // silently - they are never queued and never show up after a resume.
    try {
      _logger.d('Queuing message ${message.messageId}');
      final map = remoteMessageToMap(message);

      switch (map['data']['type']) {
        case notificationUpdateType:
          final n =
              app.Notification.fromJson(json.decode(map['data']['payload']));
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
    } finally {
      _messageMutex.release();
    }
  }

  Future<void> initMessaging() async {
    _logger.d('init Messaging');
    // Before the topics too: subscribing requests a token.
    final deletionsEnded = await _awaitFcmTokenDeletions();
    try {
      await messaging.requestPermission();
    } catch (e) {
      _logger.w(e);
      return;
    }
    // A deletion that failed, before Firebase was up or offline, or that a
    // kill interrupted. Not behind one that is still running.
    if (deletionsEnded && Settings.getFcmTokenDeletionPending()) {
      _queueFcmTokenDeletion();
      await _awaitFcmTokenDeletions();
    }
    await syncReleaseTopics();
    // Once per process: init runs again for every sign-in, and each listener
    // would handle every message once more.
    _messageSubscription ??=
        FirebaseMessaging.onMessage.listen(_handleRemoteMessage);
    _tokenRefreshSubscription ??=
        messaging.onTokenRefresh.listen(_handleFcmTokenRefresh);

    await _requestFcmToken();
    _logger.d('init Messaging done');
    _handleMessageInteraction(await messaging.getInitialMessage());
  }

  Future<void> _requestFcmToken() async {
    if (Platform.isIOS) {
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
  }

  void _queueFcmTokenDeletion() {
    // Persisted before it runs, so a kill does not lose it.
    Settings.setFcmTokenDeletionPending(true).catchError((Object e,
            StackTrace s) =>
        ErrorReporter.log('Could not record the FCM token deletion', e, s));
    _fcmTokenDeletionsQueued++;
    _fcmTokenDeletions = _fcmTokenDeletions.then((_) => _deleteFcmToken());
  }

  /// Bounded, so a deletion that never returns does not hold every later
  /// token request. Returns whether the deletions ended in time.
  Future<bool> _awaitFcmTokenDeletions() async {
    final deletions = _fcmTokenDeletions;
    try {
      await deletions.timeout(fcmTokenDeletionTimeout);
      return true;
    } on TimeoutException catch (e, s) {
      ErrorReporter.log('FCM token deletion did not finish in time', e, s);
      // The token requested meanwhile, and its topics, go with the deletion
      // once it ends.
      final epoch = AccountEpoch.current;
      unawaited(deletions.then((_) async {
        if (epoch != AccountEpoch.current) return;
        await syncReleaseTopics();
        await _requestFcmToken();
      }).catchError((Object e, StackTrace s) {
        ErrorReporter.log('Could not request an FCM token', e, s);
      }));
      return false;
    }
  }

  bool get loadingNotifications => _notificationsMutex.isLocked;

  void initNotifications(BuildContext context) {
    if (_notificationInited) return;
    _notificationInited = true;
    loadNotifications(context);
  }

  /// The account epoch the last load started under. A call made after an
  /// account change that waited for a load of the previous account fetches
  /// itself, since that load discarded its result.
  int? _notificationsLoadEpoch;

  Future<void> loadNotifications(BuildContext? context) async {
    final epoch = AccountEpoch.current;
    final locked = _notificationsMutex.isLocked;
    await _notificationsMutex.acquire();
    // A call from before an account change loads nothing, and a call joins
    // only a load of its own account.
    if (epoch != AccountEpoch.current ||
        (locked && _notificationsLoadEpoch == epoch)) {
      _notificationsMutex.release();
      return;
    }
    _notificationsLoadEpoch = epoch;
    await _storage.delete(key: messageKey);

    const limit = 10000;
    int offset = 0;
    app.NotificationResponse? response;
    // Collected separately: the visible list is only replaced once the whole
    // set has arrived, so a failure part-way leaves what the user already had.
    final fetched = <app.Notification>[];
    try {
      do {
        response = await NotificationsService.getNotifications(limit, offset);
        fetched.insertAll(0, response?.notifications.reversed ?? []);
        offset += response?.notifications.length ?? 0;
      } while (response != null && response.notifications.length == limit);
      // A fetch that outlived its account shows and stores nothing.
      if (epoch != AccountEpoch.current) return;
      notifications = fetched;
      notifyListeners();
      await NotificationsService.persist(fetched, epoch);
    } catch (e, s) {
      _logger.e('Could not load notifications: $e');
      // The stored set belongs to the last signed-in account: never shown
      // while nobody is signed in or after the account changed, and the
      // failure is not the next account's to be told about.
      if (epoch != AccountEpoch.current || !Auth().loggedIn) {
        ErrorReporter.log('Could not load notifications', e, s);
        return;
      }
      if (notifications.isEmpty) {
        // Nothing loaded this session: fall back to the last set we stored, so
        // an unreachable backend shows the previous notifications instead of
        // an empty list.
        final stored = await NotificationsService.loadPersisted();
        if (epoch != AccountEpoch.current) {
          ErrorReporter.log('Could not load notifications', e, s);
          return;
        }
        notifications = stored;
        notifyListeners();
      }
      // Recorded either way: a support dump has to show that the backend
      // failed even when the stored set covered it up. Only worth telling the
      // user about when the fallback came up empty too.
      if (notifications.isEmpty) {
        ErrorReporter.report('Could not load notifications', e, s);
      } else {
        ErrorReporter.log('Could not load notifications', e, s);
      }
    } finally {
      _notificationsMutex.release();
    }
  }

  Future<void> updateNotifications(BuildContext context, int index) async {
    try {
      await NotificationsService.setNotification(notifications[index]);
    } catch (e, s) {
      ErrorReporter.report('Could not update notification', e, s);
    }
    notifyListeners();
  }

  Future<void> deleteNotifications(List<String> ids) async {
    try {
      await NotificationsService.deleteNotifications(ids);
      // Drop them from the persisted set too, or the offline fallback would
      // bring them back on the next start without a reachable backend.
      await NotificationsService.removePersisted(ids);
    } catch (e, s) {
      ErrorReporter.report('Could not delete notifications', e, s);
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
          MaterialPageRoute(
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
    try {
      final read = await _storage.read(key: messageKey);
      final list = read != null ? json.decode(read) as List : [];
      list.map((e) => RemoteMessage.fromMap(e as Map<String, dynamic>))
          .forEach(_handleRemoteMessage);
    } finally {
      try {
        // Dropped even when handling threw, and this runs on every resume: an
        // entry that cannot be decoded would otherwise be retried forever, and
        // the ones before it re-applied each time - every release_info among
        // them schedules another update check.
        await _storage.delete(key: messageKey);
      } catch (e) {
        _logger.e('Could not clear the queued messages: $e');
      }
      _messageMutex.release();
    }
  }

  void _handleRemoteMessage(RemoteMessage message) =>
      _handleRemoteMessageCommand(message.data);

  void _handleRemoteMessageCommand(dynamic data) {
    switch (data['type']) {
      case notificationUpdateType:
        final updated =
        app.Notification.fromJson(json.decode(data['payload'] as String));
        if (updated.isRead) Eraser.clearAppNotificationsByTag(updated.id);
        // userId is the sub the token was registered under, and the account
        // key holds the signed-in sub: the token of an account signed out
        // offline may still be registered to it.
        if (updated.userId != Settings.getAccount()) {
          _logger.d('Dropped a message for another account');
          break;
        }
        final idx = notifications.indexWhere((e) => e.id == updated.id);
        if (idx != -1) {
          notifications[idx] = updated;
        } else {
          notifications.insert(0, updated);
        }
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
      // Unchanged only once registered: a token whose registration failed or
      // outlived its account is registered again when it comes back.
      if (_registeredFcmToken == token) {
        _logger.d('FCM token unchanged');
        return;
      }
      final previous = _registeredFcmToken;
      if (previous != null) {
        try {
          await FcmTokenService.deregisterFcmToken(previous);
        } catch (e, s) {
          ErrorReporter.report('Could not deregister FCM', e, s);
        }
      }
      final epoch = AccountEpoch.current;
      fcmToken = token;
      _registeredFcmToken = null;
      _logger.d('Firebase token changed');
      try {
        await FcmTokenService.registerFcmToken(token);
        if (epoch == AccountEpoch.current) _registeredFcmToken = token;
        await messaging.subscribeToTopic('announcements');
      } catch (e, s) {
        ErrorReporter.report('Could not setup FCM', e, s);
      }
    });
  }

  Future<void> clearNotificationData() async {
    // Not awaited: on an account change this runs before the next account
    // gets past the login spinner, and offline it may not return.
    _queueFcmTokenDeletion();
    fcmToken = null;
    _registeredFcmToken = null;
    notifications.clear();
    _notificationInited = false;
    _messageIdToDisplay = null;
    await _clearQueuedMessages();
  }

  /// The token may still be registered to the account signed out offline;
  /// deleted, it no longer receives that account's messages. Never throws.
  Future<void> _deleteFcmToken() async {
    try {
      await messaging.deleteToken();
      // Only by the last one queued: a later one is still to run.
      if (_fcmTokenDeletionsQueued == 1) {
        await Settings.setFcmTokenDeletionPending(false);
      }
    } catch (e) {
      _logger.w('Could not delete FCM token: $e');
    } finally {
      _fcmTokenDeletionsQueued--;
    }
    // What arrived for that account until now.
    await _clearQueuedMessages();
  }

  /// Logged, never thrown: a logout and an account change go on without it.
  Future<void> _clearQueuedMessages() async {
    try {
      await _storage.delete(key: messageKey);
    } catch (e, s) {
      ErrorReporter.log('Could not clear the queued messages', e, s);
    }
  }
}
