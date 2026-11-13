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

import 'dart:collection';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/live/client_certificate.dart';
import 'package:mobile_app/live/mqtt_connection.dart';
import 'package:mobile_app/mixins/notification_mixin.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/models/notification.dart' as app;
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/mgw/auth_service.dart';
import 'package:mobile_app/services/mgw/restricted.dart';
import 'package:mobile_app/services/mgw/storage.dart';
import 'package:mobile_app/shared/remote_message_encoder.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

/// Secure storage whose reads of [failing] keys, and deletions of
/// [failingDeletes], fail as the Android plugin answers an exception once
/// resetOnError is off.
class _Store extends MapBase<String, String> {
  final data = <String, String>{};
  final failing = <String>{};
  final failingDeletes = <String>{};

  /// Writes and deletes, in order.
  final changes = <String>[];

  @override
  String? operator [](Object? key) {
    if (failing.contains(key)) throw _keystoreError('read');
    return data[key];
  }

  @override
  void operator []=(String key, String value) {
    changes.add('write $key');
    data[key] = value;
  }

  @override
  void clear() {
    changes.add('clear');
    data.clear();
  }

  @override
  Iterable<String> get keys => data.keys;

  @override
  String? remove(Object? key) {
    if (failingDeletes.contains(key)) throw _keystoreError('delete');
    changes.add('delete $key');
    return data.remove(key);
  }
}

PlatformException _keystoreError(String method) => PlatformException(
    code: 'Exception encountered',
    message: method,
    details: 'android.security.KeyStoreException: System error');

RemoteMessage _update(String id) => RemoteMessage(data: {
      'type': notificationUpdateType,
      'payload': jsonEncode(
          app.Notification('2026-10-01T00:00:00Z', 'm', 'u', id, false, 't')
              .toJson()),
    });

void main() {
  late _Store store;
  late Map<String, String> before;
  final credentials = Auth.storageKeys.credentials;

  setUpAll(() async {
    await setUpGoldenEnvironment();
    await MgwStorage.init();
  });

  setUp(() {
    store = _Store();
    store.data[credentials] = '{"accessToken":"signed-in"}';
    FlutterSecureStorage.setMockInitialValues(store);
  });

  tearDown(() => FlutterSecureStorage.setMockInitialValues({}));

  /// Seen after the failure: nothing written or deleted, and the login
  /// tokens of Auth still there.
  void expectUntouched() {
    expect(store.changes, isEmpty);
    expect(store.data, before);
    expect(store.data[credentials], isNotNull);
  }

  group('the queued push messages', () {
    test('that cannot be read are kept for the next resume', () async {
      store.data[messageKey] = jsonEncode([]);
      store.failing.add(messageKey);
      before = Map.of(store.data);

      await AppState().handleQueuedMessages();

      expectUntouched();
    });

    test('are not replaced by a message that arrives while they cannot be '
        'read, and the next one is queued after them', () async {
      final queued = jsonEncode([remoteMessageToMap(_update('n-1'))]);
      store.data[messageKey] = queued;
      store.failing.add(messageKey);
      before = Map.of(store.data);

      await expectLater(
          NotificationMixin.queueRemoteMessage(_update('n-2')), throwsA(anything));

      expectUntouched();
      store.failing.clear();
      await NotificationMixin.queueRemoteMessage(_update('n-3'))
          .timeout(const Duration(seconds: 2));
      expect(jsonDecode(store.data[messageKey]!), hasLength(2),
          reason: 'n-1 kept, and the lock released');
    });

    test('that cannot be cleared do not keep the notifications loading',
        () async {
      serveGoldenBackend(FakeBackend());
      addTearDown(resetGoldenBackend);
      store.failingDeletes.add(messageKey);

      for (var load = 1; load <= 2; load++) {
        await AppState()
            .loadNotifications(null)
            .timeout(const Duration(seconds: 2));
      }

      expect(AppState().loadingNotifications, isFalse);
    });
  });

  group('the live install id', () {
    test('that cannot be read is not replaced', () async {
      store.data['live-mqtt-install-id'] = 'install-1';
      store.failing.add('live-mqtt-install-id');
      before = Map.of(store.data);

      await expectLater(liveInstallId(), throwsA(isA<PlatformException>()));

      expectUntouched();
      store.failing.clear();
      expect(await liveInstallId(), 'install-1');
    });
  });

  group('the live certificate', () {
    final dio = ClientCertificates.dio;
    final apiUrl = ClientCertificates.apiUrl;
    final device = ClientCertificates.device;
    final headers = ClientCertificates.headers;
    late FakeBackend backend;

    setUp(() {
      backend = FakeBackend();
      final client = Dio()..httpClientAdapter = backend;
      ClientCertificates.dio = () async => client;
      ClientCertificates.apiUrl = () => 'https://api.test';
      ClientCertificates.device = () async => ('Google', 'Pixel 7');
      ClientCertificates.headers = () async => {'Authorization': 'Bearer t'};
    });

    tearDown(() {
      ClientCertificates.dio = dio;
      ClientCertificates.apiUrl = apiUrl;
      ClientCertificates.device = device;
      ClientCertificates.headers = headers;
    });

    test('that cannot be read is not used, signed again or deleted', () async {
      store.data['live-mqtt-install-id'] = 'install-1';
      final key = ClientCertificates.keyKeyOf('test-account');
      final cert = ClientCertificates.certKeyOf('test-account');
      store.data[key] = 'key-pem';
      store.data[cert] = 'cert-pem';
      store.failing.add(cert);
      before = Map.of(store.data);

      expect(await ClientCertificates.current(), isNull);

      expectUntouched();
      expect(backend.requests, isEmpty, reason: 'a new one would replace it');
    });
  });

  group('the gateway secrets', () {
    test('that cannot be read are not called missing and are kept', () async {
      final key = MgwStorage.credentialsKeyOf('p1');
      store.data[key] =
          jsonEncode(DeviceUserCredentials('id-p1', 'login-p1', 's'));
      store.failing.add(key);
      before = Map.of(store.data);

      await expectLater(MgwStorage.LoadCredentials('p1'),
          throwsA(isNot(isA<MgwCredentialsMissing>())),
          reason: 'missing sends the user to pair the gateway again');

      expectUntouched();
    });

    test('whose session cannot be read are kept, and no login replaces it',
        () async {
      store.data[MgwStorage.credentialsKeyOf('p1')] =
          jsonEncode(DeviceUserCredentials('id-p1', 'login-p1', 's'));
      final session = MgwService.sessionKeyOf('p1');
      store.data[session] = 'session-p1';
      store.data[MgwService.sessionExpirationKeyOf('p1')] =
          '2099-01-01T00:00:00Z';
      store.failing.add(session);
      before = Map.of(store.data);
      final service = MgwService.forGateway(
          MGW('a.local', 'A', 'c1', '10.0.0.1', pairingId: 'p1'));

      await expectLater(service.obtainSession(), throwsA(anything));

      expectUntouched();
    });
  });
}
