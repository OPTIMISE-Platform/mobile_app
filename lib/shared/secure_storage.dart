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

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// What the start's check of the Android secure storage found, for this
/// process (`AppInitializer.checkSecureStorage`).
class SecureStorageHealth {
  SecureStorageHealth._();

  /// Set while the plugin answers nothing for every entry because it could
  /// not open the encrypted file; cleared once the check reset the file.
  static bool unreadable = false;

  /// Set while the check runs on past its bound: whether the file can be
  /// read is not known yet.
  static bool unknown = false;

  /// Whether an answer of nothing means the entry is absent.
  static bool get trusted => !unreadable && !unknown;

  static Future<void>? _check;

  /// Completes when the running check is done; at once without one.
  static Future<void> get checked => _check ?? Future<void>.value();

  /// Makes [GuardedSecureStorage] wait for [check], which must not throw.
  static void track(Future<void> check) => _check = check;

  @visibleForTesting
  static void resetForTest() {
    unreadable = false;
    unknown = false;
    _check = null;
  }
}

/// Thrown in place of an answer of the secure storage that cannot be
/// trusted while [SecureStorageHealth.trusted] is false.
class SecureStorageUnreadable implements Exception {
  const SecureStorageUnreadable();

  @override
  String toString() => 'SecureStorageUnreadable';
}

/// A [FlutterSecureStorage] whose callers treat an exception as "not
/// available for now". Waits for the start's check; while the file is
/// unreadable or its state unknown, a read that answers nothing, and every
/// write, deletion and readAll, throws [SecureStorageUnreadable] instead of
/// reaching the file.
class GuardedSecureStorage {
  const GuardedSecureStorage(this._storage);

  final FlutterSecureStorage _storage;

  Future<String?> read({required String key}) async {
    await SecureStorageHealth.checked;
    final value = await _storage.read(key: key);
    if (value == null && !SecureStorageHealth.trusted) {
      throw const SecureStorageUnreadable();
    }
    return value;
  }

  Future<Map<String, String>> readAll() async {
    await _ensureReadable();
    return _storage.readAll();
  }

  Future<void> write({required String key, required String value}) async {
    await _ensureReadable();
    await _storage.write(key: key, value: value);
  }

  Future<void> delete({required String key}) async {
    await _ensureReadable();
    await _storage.delete(key: key);
  }

  static Future<void> _ensureReadable() async {
    await SecureStorageHealth.checked;
    if (!SecureStorageHealth.trusted) throw const SecureStorageUnreadable();
  }
}
