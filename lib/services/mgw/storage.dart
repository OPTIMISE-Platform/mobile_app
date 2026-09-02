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

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/services/mgw/auth_service.dart';
import 'package:mobile_app/services/mgw/restricted.dart';
import 'package:path_provider/path_provider.dart';

const LOG_PREFIX = "MGW-STORAGE-SERVICE";

/// Persistence for gateway pairing.
///
/// The two secrets live in the encrypted store, the list of paired gateways in
/// the plain Hive box. The split matters: the device secret and the basic-auth
/// password mint session tokens and do not expire, so they are worth more to an
/// attacker than the session token that [MgwService] already kept encrypted.
class MgwStorage {
  // Both were Hive keys until 0.0.386. Still read once so an existing pairing
  // survives the move, then deleted from the plaintext box.
  static const _mgwCredentialsKeyPrefix = "credentials_";
  static const _mgwBasicAuthCredentialsKeyPrefix = "basic_auth_credentials_";

  static const _mgwConnectedKeyPrefix = "connected_mgws_";

  static const _credentialsKey = "mgw-device-credentials";
  static const _basicAuthKey = "mgw-basic-auth-password";

  static const _boxName = "mgw.box";
  static Box<String>? _box;

  // Same options as the rest of the app, so one corrupted store resets the same
  // way everywhere (see AppInitializer._clearCorruptedSecureStorage).
  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
  );

  static final _logger = Logger(
    printer: SimplePrinter(),
  );
  static var isInitialized = false;

  static init() async {
    if(isInitialized) return;
    Hive.init((await getApplicationDocumentsDirectory()).path);
    _box = await Hive.openBox<String>(_boxName);
    isInitialized = true;
  }

  static Future<void> StoreCredentials(DeviceUserCredentials user) async {
    await init();
    _logger.d("$LOG_PREFIX: Store mgw device credentials");
    await _secure.write(key: _credentialsKey, value: json.encode(user));
  }

  static Future<DeviceUserCredentials> LoadCredentials() async {
    await init();
    _logger.d("$LOG_PREFIX: Load mgw device credentials");
    final credentials =
        await _readAndMigrate(_credentialsKey, _mgwCredentialsKeyPrefix);
    if (credentials != null) {
      return DeviceUserCredentials.fromJson(json.decode(credentials));
    }
    throw("Credentials not stored");
  }

  static Future<void> StorePairedMGW(MGW mgw) async {
    await init();
    _logger.d("$LOG_PREFIX: Store paired mgw: ${mgw.mDNSServiceName}");
    var storedMGWs = await LoadPairedMGWs();
    storedMGWs.add(mgw);
    return await _box?.put(_mgwConnectedKeyPrefix, json.encode(storedMGWs)).then((
        value) => _box?.flush());
  }

  static Future<List<MGW>> LoadPairedMGWs() async {
    await init();
    _logger.d("$LOG_PREFIX: Load paired mgws");
    var encodedMgws = _box?.get(_mgwConnectedKeyPrefix);
    List<MGW> mgws = [];
    if(encodedMgws != null) {
      for(final mgw in jsonDecode(encodedMgws)) {
        mgws.add(MGW.fromJson(mgw));
      }
    }
    _logger.d("$LOG_PREFIX: Loaded mgws: $mgws");
    return mgws;
  }

  static Future<void> RemovePairedMGW(MGW mgw) async {
    // TODO use core-id published via mDNS as identifier. Atm this is not advertised.
    await init();
    _logger.d("$LOG_PREFIX: Remove paired mgw: ${mgw.mDNSServiceName}");
    var storedMGWs = await LoadPairedMGWs();
    var filteredMGWs = [];
    for(final storedMgw in storedMGWs) {
      if(storedMgw.hostname != mgw.hostname) {
        filteredMGWs.add(storedMgw);
      }
    }
    await MgwService.ResetSessionData();
    // One credential set covers every gateway, so dropping it when the list
    // empties is the only rule available. Where the hostname keying above
    // removes more than intended, this over-clears and costs a re-pair - better
    // than leaving a usable device secret on a phone the user unpaired.
    if (filteredMGWs.isEmpty) {
      await _clearSecrets();
    }
    return await _box?.put(_mgwConnectedKeyPrefix, json.encode(filteredMGWs)).then((
        value) => _box?.flush());
  }

  // TODO: remove loading and saving of basic auth credentials later
  static Future<void> StoreBasicAuthCredentials(String password) async {
    await init();
    _logger.d("$LOG_PREFIX: Store mgw device basic auth credentials");
    await _secure.write(key: _basicAuthKey, value: password);
  }

  static Future<String> LoadBasicAuthCredentials() async {
    await init();
    _logger.d("$LOG_PREFIX: Load mgw device basic auth credentials");
    final password = await _readAndMigrate(
        _basicAuthKey, _mgwBasicAuthCredentialsKeyPrefix);
    if (password != null) {
      return password;
    }
    throw("Credentials not stored");
  }

  /// Reads [secureKey], falling back once to the plaintext Hive entry under
  /// [legacyHiveKey] and moving it across.
  ///
  /// The plaintext copy is dropped only once the encrypted write succeeded. A
  /// Keystore that is briefly unavailable would otherwise take the pairing with
  /// it; this way the value stays readable and the move is retried on the next
  /// read.
  static Future<String?> _readAndMigrate(
      String secureKey, String legacyHiveKey) async {
    final stored = await _secure.read(key: secureKey);
    if (stored != null) return stored;

    final legacy = _box?.get(legacyHiveKey);
    if (legacy == null) return null;

    _logger.i("$LOG_PREFIX: Moving $legacyHiveKey out of the plaintext box");
    try {
      await _secure.write(key: secureKey, value: legacy);
      await _box?.delete(legacyHiveKey);
      await _box?.flush();
    } catch (e) {
      _logger.e("$LOG_PREFIX: Could not move $legacyHiveKey, keeping it: $e");
    }
    return legacy;
  }

  static Future<void> _clearSecrets() async {
    _logger.d("$LOG_PREFIX: Clear mgw secrets");
    await _secure.delete(key: _credentialsKey);
    await _secure.delete(key: _basicAuthKey);
    await _box?.delete(_mgwCredentialsKeyPrefix);
    await _box?.delete(_mgwBasicAuthCredentialsKeyPrefix);
    await _box?.flush();
  }
}
