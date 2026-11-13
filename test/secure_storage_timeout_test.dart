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
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_initializer.dart';
import 'package:mobile_app/live/mqtt_connection.dart';
import 'package:mobile_app/services/api_available.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/secure_storage.dart';

import 'fake_auth_server.dart';
import 'test_helper.dart';

const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _bound = Duration(milliseconds: 100);

Future<T> _within<T>(Future<T> future) =>
    future.timeout(const Duration(seconds: 2));

/// Waits for the check's late part, which writes to Hive.
Future<void> _lateApplied() async {
  for (var i = 0; i < 200 && SecureStorageHealth.unknown; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// The secure storage behind its platform channel. A call that [holds]
/// matches gets no answer until [answerLate], as the Android plugin answers
/// none for a call that ran into a FileNotFoundException; every other call is
/// answered after [delay], as by a slow Keystore.
class _ChannelStore {
  final data = <String, String>{};
  final calls = <String>[];
  bool Function(String method) holds = (_) => true;
  Duration delay = Duration.zero;
  final _held = <Completer<void>>[];

  Future<Object?> handle(MethodCall call) async {
    final args = (call.arguments as Map).cast<String, Object?>();
    final key = args['key'] as String?;
    calls.add('${call.method} $key');
    if (holds(call.method)) {
      final held = Completer<void>();
      _held.add(held);
      await held.future;
    } else if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    switch (call.method) {
      case 'read':
        return data[key];
      case 'write':
        data[key!] = args['value'] as String;
        return null;
      case 'delete':
        data.remove(key);
        return null;
      case 'containsKey':
        return data.containsKey(key);
      case 'readAll':
        return data;
      case 'deleteAll':
        data.clear();
        return null;
    }
    return null;
  }

  /// Answers every call held so far, and every later one without holding.
  void answerLate() {
    holds = (_) => false;
    for (final held in _held) {
      held.complete();
    }
    _held.clear();
  }

  Iterable<String> get changes =>
      calls.where((c) => !c.startsWith('read ') && !c.startsWith('containsKey'));
}

void main() {
  late _ChannelStore store;
  late Directory dir;
  final credentialsKey = Auth.storageKeys.credentials;

  setUpAll(() async {
    setUpTestEnvironment();
    if (!dotenv.isInitialized) {
      dotenv.loadFromString(
          envString: await File('.env.example').readAsString());
    }
    await Settings.init();
  });

  setUp(() async {
    await Settings.clear();
    await Settings.setAccount('test-account');
    store = _ChannelStore();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, store.handle);
    dir = await Directory.systemTemp.createTemp('secure_storage_timeout');
    final file = File('${dir.path}/FlutterSecureStorage.xml');
    await file.writeAsString('<map/>');
    AppInitializer.secureStorageFile = () async => file;
    AppInitializer.secureStorageTimeout = _bound;
    Auth.storageReadTimeout = _bound;
    Auth.serverAvailableOverride = () async => true;
    ApiAvailableService.probeOverride = () async => true;
    // An established login: the check entry and the credentials were stored.
    store.data[AppInitializer.secureStorageCheckKey] = '1';
    store.data[credentialsKey] = credentials('stored').toJson();
    await Settings.setSecureStorageCheckStored(true);
    await Settings.setCredentialsStored(true);
  });

  tearDown(() async {
    store.answerLate();
    await _lateApplied();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    AppInitializer.secureStorageTimeout = const Duration(seconds: 5);
    Auth.storageReadTimeout = const Duration(seconds: 5);
    Auth.serverAvailableOverride = null;
    ApiAvailableService.resetForTest();
    SecureStorageHealth.resetForTest();
    await Auth().resetForTest();
    await dir.delete(recursive: true);
  });

  /// The Auth branch of [AppInitializer.runDeferred] on Android.
  Future<void> start() async {
    await _within(AppInitializer.checkSecureStorage());
    await _within(Auth().init());
  }

  test('a start whose storage never answers gets past the bound to the login '
      'screen, and neither counts nor resets', () async {
    await Settings.setSecureStorageCheckFailures(
        AppInitializer.secureStorageFailureLimit - 1);

    await start();

    expect(Auth().isInitialized, isTrue);
    expect(Auth().loggedIn, isFalse, reason: 'the login screen shows');
    expect(store.changes, isEmpty, reason: 'nothing written or deleted');
    expect(Settings.getSecureStorageCheckFailures(),
        AppInitializer.secureStorageFailureLimit - 1);
    expect(Settings.getCredentialsStored(), isTrue);
    expect(SecureStorageHealth.unknown, isTrue);
    await expectLater(saveMgwBrokerCredentials('p1', 'u', 'p'),
        throwsA(isA<SecureStorageUnreadable>()),
        reason: 'while unknown, the stores write nothing');
    expect(store.changes, isEmpty);
  });

  test('three slow starts of a readable storage keep the login', () async {
    store.holds = (_) => false;
    store.delay = _bound * 2;
    final file = await AppInitializer.secureStorageFile();

    for (var run = 1; run <= AppInitializer.secureStorageFailureLimit; run++) {
      SecureStorageHealth.resetForTest();
      await _within(AppInitializer.checkSecureStorage());
      expect(SecureStorageHealth.unknown, isTrue, reason: 'start $run');
      await _lateApplied();

      expect(SecureStorageHealth.unknown, isFalse, reason: 'start $run');
      expect(Settings.getSecureStorageCheckFailures(), 0, reason: 'start $run');
    }

    expect(store.changes, isEmpty);
    expect(store.data[credentialsKey], isNotNull);
    expect(file.existsSync(), isTrue);
    expect(Settings.getSecureStorageResetPending(), isFalse);
  });

  test('a late finding counts as one in time, and Auth reads again later',
      () async {
    await start();
    // Late, and as an unopened file answers: nothing for every entry.
    store.data.clear();
    store.answerLate();
    await _lateApplied();

    expect(SecureStorageHealth.unknown, isFalse);
    expect(SecureStorageHealth.unreadable, isTrue);
    expect(Settings.getSecureStorageCheckFailures(), 1);
    expect(Auth().loggedIn, isFalse, reason: "Auth's late answer is dropped");
    expect(store.changes, isEmpty);

    store.data[credentialsKey] = credentials('stored').toJson();
    final headers = await _within(Auth().getHeaders());

    expect(headers['authorization'], 'Bearer stored');
    expect(Auth().loggedIn, isTrue);
  });

  test('a late finding at the limit resets', () async {
    await Settings.setSecureStorageCheckFailures(
        AppInitializer.secureStorageFailureLimit - 1);
    await _within(AppInitializer.checkSecureStorage());
    store.data.remove(AppInitializer.secureStorageCheckKey);

    store.answerLate();
    await _lateApplied();

    expect(store.changes, ['deleteAll null']);
    expect(Settings.getCredentialsStored(), isFalse);
    expect(SecureStorageHealth.unreadable, isFalse);
    expect(SecureStorageHealth.unknown, isFalse);
  });

  test('a reset whose deletion never answers deletes the file instead',
      () async {
    store.holds = (method) => method == 'deleteAll';
    store.data.remove(AppInitializer.secureStorageCheckKey);
    await Settings.setSecureStorageCheckFailures(
        AppInitializer.secureStorageFailureLimit - 1);
    final file = await AppInitializer.secureStorageFile();

    await _within(AppInitializer.checkSecureStorage());

    expect(store.calls, contains('deleteAll null'));
    expect(file.existsSync(), isFalse);
    expect(Settings.getSecureStorageResetPending(), isTrue);
    expect(Settings.getCredentialsStored(), isFalse);
  });
}
