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
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_initializer.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/settings.dart';

import 'golden_helper.dart';

const _check = AppInitializer.secureStorageCheckKey;
const _credentials = 'auth_credentials';

/// What flutter_secure_storage 9.2.4 on Android sends back for an exception:
/// code and method, the Java stack trace as details.
PlatformException _pluginError(String trace) => PlatformException(
    code: 'Exception encountered', message: 'read', details: trace);

/// A value that does not match the keyset of EncryptedSharedPreferences.
final _undecryptable = _pluginError(
    'java.lang.SecurityException: Could not decrypt value. decryption failed\n'
    '\tat androidx.security.crypto.EncryptedSharedPreferences.getDecryptedObject\n'
    'Caused by: java.security.GeneralSecurityException: decryption failed\n');

/// A Keystore that does not answer for a moment.
final _keystoreBusy = _pluginError(
    'android.security.KeyStoreException: System error\n'
    '\tat android.security.KeyStore2.getKeyEntry\n');

/// Secure storage whose read of the check entry fails on demand; [deleteAll]
/// of the plugin arrives as [clear], which fails with [clearError].
class _Store extends MapBase<String, String> {
  final data = <String, String>{};
  Object? checkReadError;
  Object? clearError;
  int clears = 0;

  /// Called on each read of the check entry.
  void Function()? onCheckRead;

  @override
  String? operator [](Object? key) {
    if (key == _check) onCheckRead?.call();
    final error = checkReadError;
    if (key == _check && error != null) throw error;
    return data[key];
  }

  @override
  void operator []=(String key, String value) => data[key] = value;

  @override
  void clear() {
    final error = clearError;
    if (error != null) throw error;
    clears++;
    data.clear();
  }

  @override
  Iterable<String> get keys => data.keys;

  @override
  String? remove(Object? key) => data.remove(key);
}

void main() {
  late _Store store;
  late Directory dir;
  late File file;

  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  setUp(() async {
    await Settings.clear();
    store = _Store();
    FlutterSecureStorage.setMockInitialValues(store);
    dir = await Directory.systemTemp.createTemp('secure_storage_check');
    file = File('${dir.path}/FlutterSecureStorage.xml');
    AppInitializer.secureStorageFile = () async => file;
  });

  tearDown(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await dir.delete(recursive: true);
  });

  /// A store the check has seen before, holding the login tokens.
  Future<void> established() async {
    await AppInitializer.checkSecureStorage();
    store.data[_credentials] = 'tokens';
  }

  test('no store in lib sets resetOnError, whose reset deletes the shared file',
      () {
    final offenders = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            RegExp(r'resetOnError:\s*true').hasMatch(file.readAsStringSync()))
          file.path,
    ];
    expect(offenders, isEmpty);
  });

  test('the first start writes the check entry and deletes nothing', () async {
    store.data[_credentials] = 'tokens';

    await AppInitializer.checkSecureStorage();

    expect(store.data[_check], isNotNull);
    expect(store.data[_credentials], 'tokens');
    expect(Settings.getSecureStorageCheckStored(), isTrue);
    expect(store.clears, 0);
  });

  test('a single failed read deletes nothing', () async {
    await established();
    store.checkReadError = _keystoreBusy;

    await AppInitializer.checkSecureStorage();

    expect(store.clears, 0);
    expect(store.data[_credentials], 'tokens',
        reason: 'the login tokens survive a failure in another entry');
    expect(Settings.getSecureStorageCheckFailures(), 1);
  });

  test('a read that fails on ${AppInitializer.secureStorageFailureLimit} '
      'starts in a row resets the store', () async {
    await established();
    store.checkReadError = _keystoreBusy;

    for (var start = 1;
        start < AppInitializer.secureStorageFailureLimit;
        start++) {
      await AppInitializer.checkSecureStorage();
      expect(store.clears, 0, reason: 'start $start');
    }
    await AppInitializer.checkSecureStorage();

    expect(store.clears, 1);
    expect(store.data, isEmpty);
    expect(Settings.getSecureStorageCheckFailures(), 0);
    expect(Settings.getSecureStorageCheckStored(), isFalse,
        reason: 'the next start writes the entry again');
  });

  test('a successful read resets the count', () async {
    await established();
    store.checkReadError = _keystoreBusy;
    for (var start = 1;
        start < AppInitializer.secureStorageFailureLimit;
        start++) {
      await AppInitializer.checkSecureStorage();
    }

    store.checkReadError = null;
    await AppInitializer.checkSecureStorage();
    expect(Settings.getSecureStorageCheckFailures(), 0);

    store.checkReadError = _keystoreBusy;
    await AppInitializer.checkSecureStorage();

    expect(store.clears, 0);
    expect(store.data[_credentials], 'tokens');
  });

  test('a value that no longer matches its key resets the store at once',
      () async {
    await established();
    await Settings.setCredentialsStored(true);
    store.checkReadError = _undecryptable;

    await AppInitializer.checkSecureStorage();

    expect(store.clears, 1);
    expect(store.data, isEmpty);
    expect(Settings.getCredentialsStored(), isFalse,
        reason: 'Auth would read the emptied store as one that failed');
  });

  test('a reset the plugin cannot do deletes the file now and again at the '
      'next start, before the read', () async {
    await established();
    store.checkReadError = _undecryptable;
    // Its clear decrypts every entry, and fails as the read did.
    store.clearError = _undecryptable;
    for (final f in [file, File('${file.path}.bak')]) {
      await f.writeAsString('<map/>');
    }

    await AppInitializer.checkSecureStorage();

    expect(file.existsSync(), isFalse);
    expect(File('${file.path}.bak').existsSync(), isFalse,
        reason: 'Android restores the file from it');
    expect(Settings.getSecureStorageResetPending(), isTrue);

    // This run's loaded copy went back with a write; the next start finds
    // the entries of a new file.
    await file.writeAsString('<map/>');
    store.data.clear();
    store.checkReadError = null;
    store.clearError = null;
    bool? fileAtRead;
    store.onCheckRead = () => fileAtRead ??= file.existsSync();
    await AppInitializer.checkSecureStorage();

    expect(fileAtRead, isFalse);
    expect(Settings.getSecureStorageResetPending(), isFalse);
    expect(Settings.getSecureStorageCheckStored(), isTrue,
        reason: 'the start wrote the entry again');
  });

  test('an entry that was written but reads as nothing counts as a failure '
      'and is not written again', () async {
    await established();
    // As the plugin answers when it could not open the encrypted file.
    store.data.remove(_check);

    await AppInitializer.checkSecureStorage();

    expect(store.data.containsKey(_check), isFalse);
    expect(store.clears, 0);
    expect(Settings.getSecureStorageCheckFailures(), 1);
  });

  test('the check does not read the entries of Auth', () {
    expect(_check, isNot(Auth.storageKeys.credentials));
    expect(_check, isNot(Auth.encKeyName));
  });
}
