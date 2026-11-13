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
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_initializer.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/live/client_certificate.dart';
import 'package:mobile_app/live/mqtt_connection.dart';
import 'package:mobile_app/mixins/notification_mixin.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/mgw/auth_service.dart';
import 'package:mobile_app/services/mgw/restricted.dart';
import 'package:mobile_app/services/mgw/storage.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/secure_storage.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

const _installId = 'live-mqtt-install-id';

/// Secure storage that records every write and deletion. A key it does not
/// hold reads as nothing, as every key does from the plugin while it cannot
/// open the encrypted file.
class _Store extends MapBase<String, String> {
  final data = <String, String>{};

  /// Writes, deletes and clears, in order.
  final changes = <String>[];

  @override
  String? operator [](Object? key) => data[key];

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
    changes.add('delete $key');
    return data.remove(key);
  }
}

void main() {
  late _Store store;
  late Map<String, String> before;
  final credentials = Auth.storageKeys.credentials;

  setUpAll(() async {
    await setUpGoldenEnvironment();
    await MgwStorage.init();
  });

  setUp(() async {
    store = _Store();
    store.data[credentials] = '{"accessToken":"signed-in"}';
    FlutterSecureStorage.setMockInitialValues(store);
    MgwStorage.restartForTest();
  });

  tearDown(() {
    FlutterSecureStorage.setMockInitialValues({});
    SecureStorageHealth.resetForTest();
  });

  /// Marks the file unreadable, as the start's check does.
  void unreadable() {
    SecureStorageHealth.unreadable = true;
    before = Map.of(store.data);
  }

  void expectUntouched() {
    expect(store.changes, isEmpty, reason: 'nothing written or deleted');
    expect(store.data, before);
  }

  group('the queued push messages', () {
    test('that read as nothing while the file is unreadable are kept',
        () async {
      unreadable();

      await AppState().handleQueuedMessages();

      expectUntouched();
    });

    test('are cleared as before while the file is readable', () async {
      await AppState().handleQueuedMessages();

      expect(store.changes, ['delete $messageKey']);
    });
  });

  group('the live install id', () {
    test('that reads as nothing while the file is unreadable is not replaced',
        () async {
      unreadable();

      await expectLater(
          liveInstallId(), throwsA(isA<SecureStorageUnreadable>()));

      expectUntouched();
    });

    test('that reads as a value while the file is unreadable is used',
        () async {
      store.data[_installId] = 'install-1';
      unreadable();

      expect(await liveInstallId(), 'install-1');
      expectUntouched();
    });

    test('is made and stored as before while the file is readable', () async {
      final id = await liveInstallId();

      expect(store.data[_installId], id);
      expect(store.changes, ['write $_installId']);
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
      store.data[_installId] = 'install-1';
    });

    tearDown(() {
      ClientCertificates.dio = dio;
      ClientCertificates.apiUrl = apiUrl;
      ClientCertificates.device = device;
      ClientCertificates.headers = headers;
    });

    test('that reads as nothing while the file is unreadable is not signed '
        'again', () async {
      unreadable();

      expect(await ClientCertificates.current(), isNull);

      expectUntouched();
      expect(backend.requests, isEmpty, reason: 'a new one would replace it');
    });

    test('that is missing is signed as before while the file is readable',
        () async {
      await ClientCertificates.current();

      expect(backend.requests.map((r) => r.uri.path), contains('/ca/sign'));
    });

    test('is not deleted while the file is unreadable', () async {
      store.data[ClientCertificates.certKeyOf('previous')] = 'cert-pem';
      unreadable();

      await expectLater(ClientCertificates.forget('test-account'),
          throwsA(isA<SecureStorageUnreadable>()));
      await ClientCertificates.forgetAllBut('test-account');

      expectUntouched();
    });

    for (final state in ['unreadable', 'unknown']) {
      test('of an earlier account lets a pending account wipe end while the '
          'file is $state', () async {
        store.data[ClientCertificates.certKeyOf('previous')] = 'cert-pem';
        if (state == 'unreadable') {
          SecureStorageHealth.unreadable = true;
        } else {
          SecureStorageHealth.unknown = true;
        }
        before = Map.of(store.data);
        await Settings.setAccountWipePending(true);
        addTearDown(() => Settings.setAccountWipePending(false));

        await CacheHelper.retryPendingAccountWipe();

        expect(Settings.getAccountWipePending(), isFalse,
            reason: 'a wipe still pending clears the cache at every start');
        expectUntouched();
      });
    }

    test('of an earlier account goes with an account wipe as before while '
        'the file is readable', () async {
      final previous = ClientCertificates.certKeyOf('previous');
      store.data[previous] = 'cert-pem';

      await ClientCertificates.forgetAllBut('test-account');

      expect(store.changes, ['delete $previous']);
    });
  });

  group('the gateway secrets', () {
    test('that read as nothing while the file is unreadable are not called '
        'missing', () async {
      unreadable();

      await expectLater(MgwStorage.LoadCredentials('p1'),
          throwsA(isNot(isA<MgwCredentialsMissing>())),
          reason: 'missing sends the user to pair the gateway again');

      expectUntouched();
    });

    test('that are absent are missing as before while the file is readable',
        () async {
      await expectLater(MgwStorage.LoadCredentials('p1'),
          throwsA(isA<MgwCredentialsMissing>()));
    });

    test('are not stored over while the file is unreadable', () async {
      unreadable();

      await expectLater(
          MgwStorage.StoreCredentials(
              'p1', DeviceUserCredentials('id-p1', 'login-p1', 's')),
          throwsA(isA<SecureStorageUnreadable>()));

      expectUntouched();
    });
  });

  group('the gateway session', () {
    test('that reads as nothing while the file is unreadable is not replaced '
        'by a login', () async {
      store.data[MgwStorage.credentialsKeyOf('p1')] =
          jsonEncode(DeviceUserCredentials('id-p1', 'login-p1', 's'));
      unreadable();
      final service = MgwService.forGateway(
          MGW('a.local', 'A', 'c1', '10.0.0.1', pairingId: 'p1'));

      await expectLater(
          service.obtainSession(), throwsA(isA<SecureStorageUnreadable>()));

      expectUntouched();
    });

    test('is not dropped while the file is unreadable', () async {
      unreadable();

      await MgwService.ResetSessionData('p1');

      expectUntouched();
    });

    test('is dropped as before while the file is readable', () async {
      await MgwService.ResetSessionData('p1');

      expect(store.changes, [
        'delete ${MgwService.sessionKeyOf('p1')}',
        'delete ${MgwService.sessionExpirationKeyOf('p1')}',
      ]);
    });
  });

  group('the gateway broker login', () {
    final key = mgwBrokerCredentialsKey('p1');

    test('that reads as nothing while the file is unreadable is not called '
        'absent, and none is stored over it', () async {
      unreadable();

      await expectLater(readMgwBrokerCredentials('p1'),
          throwsA(isA<SecureStorageUnreadable>()));
      await expectLater(saveMgwBrokerCredentials('p1', 'u', 'p'),
          throwsA(isA<SecureStorageUnreadable>()));

      expectUntouched();
    });

    test('is absent and stored as before while the file is readable',
        () async {
      expect(await readMgwBrokerCredentials('p1'), isNull);
      await saveMgwBrokerCredentials('p1', 'u', 'p');

      expect(store.changes, ['write $key']);
    });
  });

  group('the start check', () {
    late Directory dir;

    setUp(() async {
      await Settings.clear();
      await Settings.setAccount('test-account');
      dir = await Directory.systemTemp.createTemp('secure_storage_unreadable');
      AppInitializer.secureStorageFile =
          () async => File('${dir.path}/FlutterSecureStorage.xml');
      // A start that wrote the check entry, whose file then could not be
      // opened: every entry reads as nothing.
      await Settings.setSecureStorageCheckStored(true);
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    test('marks the file unreadable before a store reads that started '
        'with it', () async {
      before = Map.of(store.data);

      final check = AppInitializer.checkSecureStorage();
      final id = liveInstallId();
      await check;

      await expectLater(id, throwsA(isA<SecureStorageUnreadable>()));
      expect(SecureStorageHealth.unreadable, isTrue);
      expectUntouched();
    });

    test('holds a write and a deletion that start with it until its finding',
        () async {
      before = Map.of(store.data);

      final check = AppInitializer.checkSecureStorage();
      final write = expectLater(saveMgwBrokerCredentials('p1', 'u', 'p'),
          throwsA(isA<SecureStorageUnreadable>()));
      final deletion = expectLater(ClientCertificates.forget('test-account'),
          throwsA(isA<SecureStorageUnreadable>()));
      await check;

      await write;
      await deletion;
      expectUntouched();
    });

    test('ends the state once it reset the file', () async {
      await Settings.setSecureStorageCheckFailures(
          AppInitializer.secureStorageFailureLimit - 1);

      await AppInitializer.checkSecureStorage();

      expect(store.changes, ['clear']);
      expect(SecureStorageHealth.unreadable, isFalse);
      final id = await liveInstallId();
      expect(store.data[_installId], id, reason: 'empty is empty now');
    });
  });
}
