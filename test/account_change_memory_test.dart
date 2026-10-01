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
import 'dart:collection';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_initializer.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/mixins/notification_mixin.dart';
import 'package:mobile_app/models/notification.dart' as app;
import 'package:mobile_app/models/device_class.dart';
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/models/sensor_tab.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/services/device_classes.dart';
import 'package:mobile_app/services/device_types.dart';
import 'package:mobile_app/services/mgw/storage.dart';
import 'package:hive/hive.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/account_epoch.dart';
import 'package:openidconnect/openidconnect.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 300 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// loadNetworks takes a context it does not read.
class _Context extends Fake implements BuildContext {}

/// Secure storage whose delete of the message queue fails.
class _QueueUndeletable extends MapBase<String, String> {
  final _values = <String, String>{};

  @override
  String? operator [](Object? key) => _values[key];

  @override
  void operator []=(String key, String value) => _values[key] = value;

  @override
  void clear() => _values.clear();

  @override
  Iterable<String> get keys => _values.keys;

  @override
  String? remove(Object? key) {
    if (key == messageKey) throw PlatformException(code: "keystore");
    return _values.remove(key);
  }
}

/// The identity package's own secure storage, as its method channel sees it.
final _identityStorage = <String, String>{};

void _mockIdentityStorage() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('plugins.concerti.io/openidconnect_secure_storage'),
          (call) async {
    final args = (call.arguments as Map?)?.cast<String, Object?>() ?? {};
    final key = args['key'] as String?;
    switch (call.method) {
      case 'write':
        _identityStorage[key!] = args['value'] as String;
        return null;
      case 'read':
        return _identityStorage[key];
      case 'delete':
        _identityStorage.remove(key);
        return null;
      case 'containsKey':
        return _identityStorage.containsKey(key);
    }
    return null;
  });
}

RemoteMessage _update(String id, String userId) => RemoteMessage(data: {
      "type": notificationUpdateType,
      "payload": jsonEncode(
          app.Notification("2026-10-01T00:00:00Z", "m", userId, id, false, "t")
              .toJson()),
    });

/// An identity whose id token carries [sub], the only claim the switch reads.
OpenIdIdentity _identity(String sub) {
  String part(Map<String, dynamic> claims) =>
      base64Url.encode(utf8.encode(jsonEncode(claims))).replaceAll("=", "");
  return OpenIdIdentity(
    accessToken: "access",
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    idToken: "${part({"alg": "none"})}.${part({"sub": sub})}.sig",
    tokenType: "bearer",
  );
}

/// Hands out [token] until a deletion completes, which, as on a phone, makes
/// the next request return a new one.
class _FakeMessaging extends Fake implements FirebaseMessaging {
  String token = "token-a";
  String nextToken = "token-b";
  int deletes = 0;
  int tokenRefreshListens = 0;
  bool deleteFails = false;

  /// Numbers of the deletions, counted from 1, that fail.
  final failingDeletes = <int>{};
  Completer<void>? holdDelete;
  final refreshes = StreamController<String>.broadcast();

  @override
  Future<void> deleteToken() async {
    final number = ++deletes;
    await holdDelete?.future;
    if (deleteFails || failingDeletes.contains(number)) {
      throw Exception("SERVICE_NOT_AVAILABLE");
    }
    token = nextToken;
  }

  @override
  Future<String?> getToken({String? vapidKey, String? serviceWorkerScriptPath}) async =>
      token;

  @override
  Stream<String> get onTokenRefresh {
    tokenRefreshListens++;
    return refreshes.stream;
  }

  final topics = <String>[];

  @override
  Future<void> subscribeToTopic(String topic) async => topics.add(topic);

  @override
  Future<void> unsubscribeFromTopic(String topic) async {}

  @override
  Future<RemoteMessage?> getInitialMessage() async => null;

  // requestPermission has a long list of named parameters; only its result
  // matters here.
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #requestPermission) {
      return Future.value(const NotificationSettings(
        alert: AppleNotificationSetting.notSupported,
        announcement: AppleNotificationSetting.notSupported,
        authorizationStatus: AuthorizationStatus.authorized,
        badge: AppleNotificationSetting.notSupported,
        carPlay: AppleNotificationSetting.notSupported,
        lockScreen: AppleNotificationSetting.notSupported,
        notificationCenter: AppleNotificationSetting.notSupported,
        showPreviews: AppleShowPreviewSetting.notSupported,
        timeSensitive: AppleNotificationSetting.notSupported,
        criticalAlert: AppleNotificationSetting.notSupported,
        sound: AppleNotificationSetting.notSupported,
        providesAppNotificationSettings:
            AppleNotificationSetting.notSupported,
      ));
    }
    return super.noSuchMethod(invocation);
  }
}

Map<String, dynamic> _location(String id) => {
      "id": id,
      "name": id,
      "description": "",
      "image": "",
      "device_ids": <String>[],
      "device_group_ids": <String>[],
    };

Map<String, dynamic> _group(String id) => {
      "id": id,
      "name": id,
      "image": "",
      "criteria": <Map<String, dynamic>>[],
      "device_ids": <String>[],
      "attributes": null,
    };

Map<String, dynamic> _network(String id) => {
      "id": id,
      "name": id,
      "hash": "",
      "owner_id": "owner-1",
      "shared": false,
      "device_local_ids": <String>[],
      "device_ids": <String>[],
      "connection_state": "online",
    };

void main() {
  late FakeBackend backend;
  // One for the file: the token refresh listener stays on the first instance.
  final messaging = _FakeMessaging();

  int requestsTo(String method, String path) => backend.requests
      .where((r) => r.method == method && r.uri.path == path)
      .length;

  /// Serves what [account] has: one location, group, network, aspect, device
  /// type and device class, each named after it.
  void serveAccount(String account) {
    backend.serveJson("GET", "/device-repository/locations", 200,
        [_location("location-$account")]);
    backend.serveJson("GET", "/device-repository/device-groups", 200,
        [_group("group-$account")]);
    backend.serveJson("GET", "/device-repository/device-groups/group-$account",
        200, _group("group-$account"));
    backend.serveJson("GET", "/device-repository/extended-hubs", 200,
        [_network("network-$account")]);
    backend.serveJson("GET", "/device-repository/aspects", 200, [
      {"id": "aspect-$account", "name": account, "sub_aspects": null}
    ]);
    AppState().fetchDeviceTypes = (maxAge, {serveStale}) async => [
          DeviceType.fromJson(
              deviceTypeJson("type-$account", deviceClassId: "class-$account"))
        ];
    AppState().fetchDeviceClasses = (maxAge, {serveStale}) async =>
        [DeviceClass("class-$account", account, "")];
  }

  /// Signs [account] in as far as AppState goes, and loads what the tabs load.
  Future<void> signInAndLoad(String account) async {
    Auth().loggedIn = true;
    await AppState().ensureInitialized();
    await _until(() =>
        !AppState().loadingLocations() && AppState().locations.isNotEmpty);
    await AppState().loadDeviceGroups();
    await AppState().loadNetworks(_Context());
  }

  Map<String, Iterable<String>> loaded() => {
        "locations": AppState().locations.map((l) => l.id),
        "groups": AppState().deviceGroups.map((g) => g.id),
        "networks": AppState().networks.map((n) => n.id),
        "aspects": AppState().aspects.keys,
        "device types": AppState().deviceTypes.keys,
        "device classes": AppState().deviceClasses.keys,
      };

  setUpAll(() async {
    await setUpGoldenEnvironment();
    await MgwStorage.init();
  });

  setUp(() async {
    backend = FakeBackend();
    serveGoldenBackend(backend);
    await Settings.clear();
    await Settings.setAccount("a");
    Auth.serverAvailableOverride = () async => false;
    messaging
      ..token = "token-a"
      ..nextToken = "token-b"
      ..deletes = 0
      ..deleteFails = false
      ..holdDelete = null
      ..topics.clear()
      ..failingDeletes.clear();
    AppState().messagingOverride = messaging;
  });

  tearDown(() async {
    final hold = messaging.holdDelete;
    if (hold != null && !hold.isCompleted) hold.complete();
    messaging.deleteFails = false;
    CacheHelper.beforeAccountWipeForTest = null;
    CacheHelper.afterAccountKeyForTest = null;
    FlutterSecureStorage.setMockInitialValues({});
    // Through the fake, so no deletion is left pending for the next test.
    await AppState().onLogout();
    await AppState().fcmTokenDeletionsForTest;
    AppState().fcmTokenDeletionTimeout = const Duration(seconds: 10);
    AppState().messagingOverride = null;
    NotificationMixin.releaseTopicsSupported = () => false;
    await Settings.setAccountWipePending(false);
    await Settings.setFcmTokenDeletionPending(false);
    resetAppStateForGolden();
    resetGoldenBackend();
    Auth.serverAvailableOverride = null;
    Auth().loggedIn = false;
    AppState().fetchDeviceTypes = (maxAge, {serveStale}) =>
        DeviceTypesService.getDeviceTypes(null, maxAge, serveStale);
    AppState().fetchDeviceClasses = (maxAge, {serveStale}) =>
        DeviceClassesService.getDeviceClasses(
            maxAge: maxAge, serveStale: serveStale);
  });

  group("in memory", () {
    test("an account change after an offline logout drops what the previous "
        "account loaded, and the next account's init loads its own", () async {
      serveAccount("a");
      await signInAndLoad("a");
      expect(loaded(), {
        "locations": ["location-a"],
        "groups": ["group-a"],
        "networks": ["network-a"],
        "aspects": ["aspect-a"],
        "device types": ["type-a"],
        "device classes": ["class-a"],
      });
      expect(AppState().initialized, isTrue);

      await Auth().onLogoutForTest();
      expect(Auth().loggedIn, isFalse);
      expect(AppState().locations.map((l) => l.id), ["location-a"],
          reason: "an offline logout keeps the state in memory");

      await Auth().rememberAccountForTest(_identity("b"));

      expect(Settings.getAccount(), "b");
      for (final entry in loaded().entries) {
        expect(entry.value, isEmpty, reason: "${entry.key} of account a");
      }
      expect(AppState().initialized, isFalse,
          reason: "otherwise the next account's init is skipped");

      serveAccount("b");
      await signInAndLoad("b");

      expect(AppState().initialized, isTrue);
      expect(loaded(), {
        "locations": ["location-b"],
        "groups": ["group-b"],
        "networks": ["network-b"],
        "aspects": ["aspect-b"],
        "device types": ["type-b"],
        "device classes": ["class-b"],
      });
    });

    test("an init of the previous account that outlives the change leaves "
        "the next one uninitialized", () async {
      serveAccount("a");
      final gate = Completer<void>();
      var reads = 0;
      AppState().fetchDeviceClasses = (maxAge, {serveStale}) async {
        reads++;
        await gate.future;
        return [DeviceClass("class-a", "a", "")];
      };
      Auth().loggedIn = true;

      final old = AppState().init();
      await _until(() => reads == 1);
      expect(reads, 1);
      await Auth().onLogoutForTest();
      await Auth().rememberAccountForTest(_identity("b"));
      gate.complete();
      await old;

      expect(AppState().initialized, isFalse);
      expect(AppState().deviceClasses, isEmpty);
    });

    test("the login and its OIDC event switch the account once", () async {
      final epoch = AccountEpoch.current;

      await Future.wait([
        Auth().rememberAccountForTest(_identity("b")),
        Auth().rememberAccountForTest(_identity("b")),
      ]);

      expect(AccountEpoch.current, epoch + 1,
          reason: "a second switch would wipe what the first one let in");
      expect(Settings.getAccount(), "b");
    });

    test("an offline logout and a sign-in of the same account keep the state "
        "and leave nothing loading", () async {
      serveAccount("a");
      await signInAndLoad("a");
      final before = loaded();
      final epoch = AccountEpoch.current;

      await Auth().onLogoutForTest();
      await Auth().rememberAccountForTest(_identity("a"));
      Auth().loggedIn = true;

      expect(AccountEpoch.current, epoch);
      expect(loaded(), before);
      expect(AppState().initialized, isTrue);
      expect(AppState().loadingLocations(), isFalse);
      expect(AppState().loadingDeviceGroups(), isFalse);
      expect(AppState().loadingNetworks(), isFalse);
      expect(AppState().loadingDevices, isFalse);
      expect(AppState().loadingDeviceClasses, isFalse);
      expect(AppState().loadingNotifications, isFalse);

      backend.serveJson("GET", "/device-repository/locations", 200,
          [_location("location-a2")]);
      await AppState().loadLocations();
      expect(AppState().locations.map((l) => l.id), ["location-a2"],
          reason: "a load after the sign-in still lands");
    });

    test("a wipe that keeps failing is retried without resetting the next "
        "account's session", () async {
      serveAccount("a");
      await signInAndLoad("a");
      CacheHelper.beforeAccountWipeForTest = () => throw Exception("disk full");
      await Auth().onLogoutForTest();
      final epoch = AccountEpoch.current;

      await Auth().rememberAccountForTest(_identity("b"));
      expect(AccountEpoch.current, epoch + 1);
      expect(AppState().locations, isEmpty);
      expect(Settings.getAccount(), "b");
      expect(Settings.getAccountWipePending(), isTrue);
      expect(messaging.deletes, 1);

      serveAccount("b");
      await signInAndLoad("b");
      final session = loaded();
      // Every token refresh of b retries the wipe.
      await Auth().rememberAccountForTest(_identity("b"));

      expect(AccountEpoch.current, epoch + 1);
      expect(loaded(), session);
      expect(AppState().initialized, isTrue);
      expect(messaging.deletes, 1, reason: "b's token stays");
      expect(Settings.getAccountWipePending(), isTrue);

      CacheHelper.beforeAccountWipeForTest = null;
      await Settings.setCacheUpdated("devices");
      await Auth().rememberAccountForTest(_identity("b"));

      expect(Settings.getAccountWipePending(), isFalse);
      expect(AccountEpoch.current, epoch + 1);
      expect(loaded(), session);
      expect(Settings.getCacheUpdated("devices"), isNull,
          reason: "the refresh refills what the wipe dropped");
    });

    test("with a wipe pending, the next account has its own settings, "
        "favorites and messages", () async {
      await Settings.setFavoriteDeviceIds({"device-a"});
      await Settings.setSensorTabs([const SensorTab(id: "tab-a", name: "a")]);
      CacheHelper.beforeAccountWipeForTest = () => throw Exception("disk full");

      await Auth().rememberAccountForTest(_identity("b"));
      expect(Settings.getAccountWipePending(), isTrue);

      expect(Settings.getFavoriteDeviceIds(), isEmpty);
      expect(Settings.getSensorTabs(), isEmpty);
      await Settings.setSensorTabs([const SensorTab(id: "tab-b", name: "b")]);
      await NotificationMixin.queueRemoteMessage(_update("n-a", "a"));
      await NotificationMixin.queueRemoteMessage(_update("n-b", "b"));
      await AppState().handleQueuedMessages();
      expect(AppState().notifications.map((n) => n.id), ["n-b"]);

      await Settings.setAccount("a");
      expect(Settings.getFavoriteDeviceIds(), {"device-a"});
      expect(Settings.getSensorTabs().map((t) => t.id), ["tab-a"]);
    });

    test("a wipe that failed for b still runs when a signs in again", () async {
      var wipes = 0;
      CacheHelper.beforeAccountWipeForTest = () {
        wipes++;
        throw Exception("disk full");
      };
      await Auth().rememberAccountForTest(_identity("b"));
      serveAccount("b");
      await signInAndLoad("b");
      await Auth().onLogoutForTest();
      CacheHelper.beforeAccountWipeForTest = () => wipes++;
      await Settings.setCacheUpdated("devices");

      await Auth().rememberAccountForTest(_identity("a"));

      expect(wipes, 2);
      expect(Settings.getAccountWipePending(), isFalse);
      expect(Settings.getCacheUpdated("devices"), isNull);
      for (final entry in loaded().entries) {
        expect(entry.value, isEmpty, reason: "${entry.key} of account b");
      }
    });

    test("the switch writes the new key before it wipes, and records the "
        "token deletion before it resets", () async {
      String? keyAtWipe;
      bool? deletionRecorded;
      CacheHelper.beforeAccountWipeForTest = () => keyAtWipe = Settings.getAccount();
      CacheHelper.afterAccountKeyForTest =
          () => deletionRecorded = Settings.getFcmTokenDeletionPending();

      await Auth().rememberAccountForTest(_identity("b"));

      expect(keyAtWipe, "b");
      expect(deletionRecorded, isTrue,
          reason: "a kill before the reset must not lose it");
    });

    test("the app start retries a pending wipe once the cache is open",
        () async {
      await Settings.setAccountWipePending(true);
      await Settings.setCacheUpdated("devices");

      await AppInitializer.openCache(() async => null);

      expect(Settings.getAccountWipePending(), isFalse);
      expect(Settings.getCacheUpdated("devices"), isNull);
    });

    test("a pending wipe survives a restart and runs at the next start",
        () async {
      CacheHelper.beforeAccountWipeForTest = () => throw Exception("disk full");
      await Auth().rememberAccountForTest(_identity("b"));
      CacheHelper.beforeAccountWipeForTest = null;
      await Settings.setCacheUpdated("devices");
      await AppState().fcmTokenDeletionsForTest;

      await Settings.close();
      await Settings.init();
      expect(Settings.getAccountWipePending(), isTrue);
      await CacheHelper.retryPendingAccountWipe();

      expect(Settings.getAccountWipePending(), isFalse);
      expect(Settings.getCacheUpdated("devices"), isNull);
    });

    test("unkeyed sensor tabs go to the account signed out, also when the "
        "next one reads first", () async {
      await Hive.box<String>("settings.box").put(
          "sensor_tabs", jsonEncode([const SensorTab(id: "tab-a", name: "a")]));

      await Auth().rememberAccountForTest(_identity("b"));
      expect(Settings.getSensorTabs(), isEmpty);

      await Auth().rememberAccountForTest(_identity("a"));
      expect(Settings.getSensorTabs().map((t) => t.id), ["tab-a"]);
    });

    test("a late event of the client dropped by an offline logout leaves the "
        "next session alone", () async {
      final oldClient = StreamController<AuthEvent>();
      Auth().listenToClientEventsForTest(oldClient.stream);
      await Auth().onLogoutForTest();
      expect(Auth().clientListenerRegistered, isFalse);
      serveAccount("a");
      await signInAndLoad("a");
      final epoch = AccountEpoch.current;
      Auth.serverAvailableOverride = () async => true;

      oldClient.add(const AuthEvent(AuthEventTypes.Error));
      await pumpEventQueue();

      expect(Auth().loggedIn, isTrue);
      expect(AccountEpoch.current, epoch);
      expect(AppState().locations, isNotEmpty);
      await oldClient.close();
    });

    test("a message queue that cannot be cleared does not stop the switch",
        () async {
      serveAccount("a");
      await signInAndLoad("a");
      await Settings.setCacheUpdated("devices");
      FlutterSecureStorage.setMockInitialValues(_QueueUndeletable());
      var notified = 0;
      void count() => notified++;
      AppState().addListener(count);
      addTearDown(() => AppState().removeListener(count));

      await Auth().onLogoutForTest();
      await Auth().rememberAccountForTest(_identity("b"));

      expect(Settings.getAccount(), "b");
      expect(AppState().locations, isEmpty);
      expect(notified, greaterThan(0));
      expect(Settings.getCacheUpdated("devices"), isNull);
    });

    test("a logout resets the state in memory before it awaits anything",
        () async {
      serveAccount("a");
      await signInAndLoad("a");

      final reset = AppState().onLogout();
      for (final entry in loaded().entries) {
        expect(entry.value, isEmpty, reason: entry.key);
      }
      expect(AppState().initialized, isFalse);
      await reset;
    });

    test("an offline logout clears the stored identity and keeps the account "
        "key and its favorites", () async {
      _mockIdentityStorage();
      await _identity("a").save();
      expect((await OpenIdIdentity.load())?.sub, "a");
      await Settings.setFavoriteDeviceIds({"device-1"});

      await Auth().onLogoutForTest();

      expect(await OpenIdIdentity.load(), isNull,
          reason: "the next login must not resume it");
      expect(Settings.getAccount(), "a");
      expect(Settings.getFavoriteDeviceIds(), {"device-1"});
    });
  });

  group("FCM token", () {
    const tokens = "/notifications-v2/fcm-tokens";

    setUp(() {
      for (final token in ["token-a", "token-b"]) {
        backend.serveJson("POST", "$tokens/$token", 200, {});
        backend.serveJson("DELETE", "$tokens/$token", 200, {});
      }
    });

    test("an account change deletes the token, and the next account "
        "registers a new one", () async {
      await AppState().initMessaging();
      expect(requestsTo("POST", "$tokens/token-a"), 1);

      await Auth().onLogoutForTest();
      expect(messaging.deletes, 0, reason: "an offline logout keeps it");
      await Auth().rememberAccountForTest(_identity("b"));
      expect(messaging.deletes, 1,
          reason: "it may still be registered to account a");
      expect(AppState().fcmToken, isNull);

      await AppState().initMessaging();

      expect(requestsTo("POST", "$tokens/token-b"), 1);
      expect(requestsTo("DELETE", "$tokens/token-a"), 0,
          reason: "not deregistered under account b");
      expect(AppState().fcmToken, "token-b");
    });

    test("the switch does not wait for the deletion, the next token request "
        "does", () async {
      await AppState().initMessaging();
      messaging.holdDelete = Completer<void>();

      await Auth()
          .rememberAccountForTest(_identity("b"))
          .timeout(const Duration(seconds: 5));
      final init = AppState().initMessaging();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      messaging.holdDelete!.complete();
      await init;

      expect(requestsTo("POST", "$tokens/token-a"), 1,
          reason: "only account a registered the deleted token");
      expect(requestsTo("POST", "$tokens/token-b"), 1);
    });

    test("a registration answered after the account change is registered "
        "again for the next account", () async {
      // The deletion fails offline, so the next account gets the same token.
      messaging.deleteFails = true;
      final gate = Completer<void>();
      backend.holds["POST $tokens/token-a"] = gate;

      final old = AppState().initMessaging();
      await _until(() => requestsTo("POST", "$tokens/token-a") == 1);
      expect(requestsTo("POST", "$tokens/token-a"), 1);
      await Auth().onLogoutForTest();
      await Auth().rememberAccountForTest(_identity("b"));
      backend.holds.remove("POST $tokens/token-a");
      gate.complete();
      await old;
      await AppState().initMessaging();

      expect(requestsTo("POST", "$tokens/token-a"), 2,
          reason: "the first registration was for account a");
    });

    test("a token whose registration failed is registered when it comes back",
        () async {
      backend.failures["POST $tokens/token-a"] =
          DioExceptionType.connectionError;
      await AppState().initMessaging();
      expect(requestsTo("POST", "$tokens/token-a"), 1);

      backend.failures.remove("POST $tokens/token-a");
      messaging.refreshes.add("token-a");
      await _until(() => requestsTo("POST", "$tokens/token-a") == 2);

      expect(requestsTo("POST", "$tokens/token-a"), 2);
    });

    test("every sign-in's init listens for token refreshes only once",
        () async {
      for (var i = 0; i < 3; i++) {
        await AppState().initMessaging();
      }

      expect(messaging.tokenRefreshListens, 1);
    });

    test("a second switch deletes only after the first deletion ended",
        () async {
      await AppState().initMessaging();
      messaging.holdDelete = Completer<void>();
      await Auth().rememberAccountForTest(_identity("b"));
      await Auth().rememberAccountForTest(_identity("c"));
      await pumpEventQueue();

      expect(messaging.deletes, 1);
      messaging.holdDelete!.complete();
      await AppState().initMessaging();

      expect(messaging.deletes, 2);
      expect(requestsTo("POST", "$tokens/token-b"), 1);
    });

    test("a deletion that failed, as before Firebase is up, runs before the "
        "next token request", () async {
      await AppState().initMessaging();
      messaging.deleteFails = true;
      await Auth().rememberAccountForTest(_identity("b"));
      expect(messaging.token, "token-a", reason: "the deletion failed");

      messaging.deleteFails = false;
      await AppState().initMessaging();

      expect(messaging.deletes, 2);
      expect(requestsTo("POST", "$tokens/token-b"), 1);
      expect(requestsTo("POST", "$tokens/token-a"), 1,
          reason: "only account a registered the old token");
    });

    test("a deletion that does not end in time holds the token request only "
        "that long, and its new token is registered once it ends", () async {
      await AppState().initMessaging();
      AppState().fcmTokenDeletionTimeout = const Duration(milliseconds: 50);
      messaging.holdDelete = Completer<void>();
      await Auth().rememberAccountForTest(_identity("b"));

      await AppState().initMessaging().timeout(const Duration(seconds: 5));
      expect(requestsTo("POST", "$tokens/token-a"), 2,
          reason: "the old token, which the deletion has not reached yet");
      messaging.holdDelete!.complete();
      await _until(() => requestsTo("POST", "$tokens/token-b") == 1);

      expect(requestsTo("POST", "$tokens/token-b"), 1);
    });

    test("a pending deletion survives a restart and runs before the next "
        "token request", () async {
      await AppState().initMessaging();
      messaging.deleteFails = true;
      await Auth().rememberAccountForTest(_identity("b"));
      await AppState().fcmTokenDeletionsForTest;

      await Settings.close();
      await Settings.init();
      expect(Settings.getFcmTokenDeletionPending(), isTrue);
      messaging.deleteFails = false;
      await AppState().initMessaging();

      expect(Settings.getFcmTokenDeletionPending(), isFalse);
      expect(requestsTo("POST", "$tokens/token-b"), 1);
    });

    test("a token request does not queue a pending deletion behind one that "
        "is still running", () async {
      await AppState().initMessaging();
      AppState().fcmTokenDeletionTimeout = const Duration(milliseconds: 50);
      messaging.holdDelete = Completer<void>();
      await Auth().rememberAccountForTest(_identity("b"));

      await AppState().initMessaging();
      messaging.holdDelete!.complete();
      await AppState().fcmTokenDeletionsForTest;
      await _until(() => requestsTo("POST", "$tokens/token-b") == 1);

      expect(messaging.deletes, 1);
    });

    test("a deletion that ends late after a further switch requests no token "
        "for the account it was waited for under", () async {
      await AppState().initMessaging();
      AppState().fcmTokenDeletionTimeout = const Duration(milliseconds: 50);
      messaging.holdDelete = Completer<void>();
      await Auth().rememberAccountForTest(_identity("b"));
      await AppState().initMessaging();
      final tokenRequests = requestsTo("POST", "$tokens/token-a");
      await Auth().rememberAccountForTest(_identity("c"));

      messaging.holdDelete!.complete();
      await AppState().fcmTokenDeletionsForTest;
      await pumpEventQueue();

      expect(requestsTo("POST", "$tokens/token-b"), 0);
      expect(requestsTo("POST", "$tokens/token-a"), tokenRequests);
    });

    test("a deletion that succeeds keeps the flag of one queued after it that "
        "fails", () async {
      messaging.holdDelete = Completer<void>();
      messaging.failingDeletes.add(2);
      await Auth().rememberAccountForTest(_identity("b"));
      await Auth().rememberAccountForTest(_identity("c"));
      messaging.holdDelete!.complete();
      await AppState().fcmTokenDeletionsForTest;

      expect(messaging.deletes, 2);
      expect(Settings.getFcmTokenDeletionPending(), isTrue);
    });

    test("a deletion that ends late takes the release topics along, and they "
        "are subscribed again", () async {
      NotificationMixin.releaseTopicsSupported = () => true;
      await AppState().initMessaging();
      AppState().fcmTokenDeletionTimeout = const Duration(milliseconds: 50);
      messaging.holdDelete = Completer<void>();
      await Auth().rememberAccountForTest(_identity("b"));
      await AppState().initMessaging();
      messaging.topics.clear();

      messaging.holdDelete!.complete();
      await _until(() => requestsTo("POST", "$tokens/token-b") == 1);

      expect(messaging.topics, contains(releaseTopic));
    });

    test("a message for another account is dropped", () async {
      await NotificationMixin.queueRemoteMessage(_update("n-a", "a"));
      await NotificationMixin.queueRemoteMessage(_update("n-b", "b"));

      await AppState().handleQueuedMessages();

      expect(AppState().notifications.map((n) => n.id), ["n-a"]);
    });

    test("messages queued until the deletion ended are dropped with it",
        () async {
      messaging.holdDelete = Completer<void>();
      await Auth().rememberAccountForTest(_identity("b"));
      await NotificationMixin.queueRemoteMessage(_update("n-a", "a"));
      messaging.holdDelete!.complete();
      await AppState().fcmTokenDeletionsForTest;
      await Settings.setAccount("a");

      await AppState().handleQueuedMessages();

      expect(AppState().notifications, isEmpty);
    });
  });
}
