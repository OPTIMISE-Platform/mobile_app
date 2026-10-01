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

import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/services/mgw/auth_service.dart';
import 'package:mobile_app/services/mgw/gateway_host.dart';
import 'package:mobile_app/services/mgw/restricted.dart';
import 'package:mutex/mutex.dart';
import 'package:path_provider/path_provider.dart';

const LOG_PREFIX = "MGW-STORAGE-SERVICE";

/// No device credentials are stored, as opposed to a store that failed to read.
class MgwCredentialsMissing implements Exception {
  @override
  String toString() => "No pairing credentials are stored";
}

/// Persistence for gateway pairing.
///
/// The device secret lives in the encrypted store, the list of paired
/// gateways in the plain Hive box. It mints session tokens and does not
/// expire, so it is worth more to an attacker than the session token that
/// [MgwService] already kept encrypted.
class MgwStorage {
  // Was a Hive key until 0.0.386. Still read once so an existing pairing
  // survives the move, then deleted from the plaintext box.
  static const _mgwCredentialsKeyPrefix = "credentials_";

  static const _mgwConnectedKeyPrefix = "connected_mgws_";

  static const _credentialsKey = "mgw-device-credentials";

  // The basic-auth path was removed with the old, port-based gateway
  // generation. These two keys are kept only so init() can delete any
  // leftover password instead of leaving it on the device.
  static const _basicAuthKey = "mgw-basic-auth-password";
  static const _mgwBasicAuthCredentialsKeyPrefix = "basic_auth_credentials_";

  static const _boxName = "mgw.box";
  static Box<String>? _box;

  // Every change to the gateway list reads and writes the whole list, so two
  // unserialized changes (a pairing during an address refresh) lose one.
  static final _listLock = Mutex();

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
    // One-time cleanup of the basic-auth password left over from the old,
    // port-based gateway generation. Deliberately not awaited: this runs on the
    // startup path, and the first secure-storage access pays the one-off
    // EncryptedSharedPreferences crypto init that AppInitializer keeps off it.
    unawaited(_dropLegacyBasicAuth());
  }

  static Future<void> _dropLegacyBasicAuth() async {
    try {
      await _secure.delete(key: _basicAuthKey);
      await _box?.delete(_mgwBasicAuthCredentialsKeyPrefix);
    } catch (e) {
      _logger.e("$LOG_PREFIX: Could not drop the legacy basic auth password: $e");
    }
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
    throw MgwCredentialsMissing();
  }

  /// Whether [a] and [b] are the same gateway: the core id decides when both
  /// carry one, otherwise the hostname or the address, unless both are bound
  /// to different networks.
  static bool isSameGateway(MGW a, MGW b) {
    if (a.coreId.isNotEmpty && b.coreId.isNotEmpty) return a.coreId == b.coreId;
    if (a.networkId.isNotEmpty &&
        b.networkId.isNotEmpty &&
        a.networkId != b.networkId) {
      return false;
    }
    final sameHost = a.hostname.isNotEmpty &&
        a.hostname.toLowerCase() == b.hostname.toLowerCase();
    return sameHost || sameGatewayAddress(a.ip, b.ip);
  }

  /// Whether [a] and [b] are the same stored entry, field for field.
  static bool isSameEntry(MGW a, MGW b) =>
      a.hostname == b.hostname &&
      a.ip == b.ip &&
      a.coreId == b.coreId &&
      a.networkId == b.networkId;

  /// The entry in [stored] that [mgw], a possibly older copy, stands for.
  ///
  /// Matched on what does not change while paired: the core id, or the
  /// hostname and network without one. The address does not count, as the
  /// address refresh rewrites it. Among several matches the field-exact one
  /// wins, then the one bound to the same network.
  static MGW? resolve(MGW mgw, List<MGW> stored) {
    final candidates = mgw.coreId.isNotEmpty
        ? stored.where((m) => m.coreId == mgw.coreId).toList()
        : stored
            .where((m) =>
                m.hostname.toLowerCase() == mgw.hostname.toLowerCase() &&
                m.networkId == mgw.networkId)
            .toList();
    if (candidates.length <= 1) return candidates.firstOrNull;
    return candidates.where((m) => isSameEntry(m, mgw)).firstOrNull ??
        candidates.where((m) => m.networkId == mgw.networkId).firstOrNull ??
        candidates.first;
  }

  /// Stores [mgw], replacing every entry for the same gateway and [replacing]
  /// at the position of the first one, so pairing again does not add a second
  /// entry.
  ///
  /// An entry added by address carries no core id or mDNS name; replacing a
  /// discovered entry with it keeps those, so the gateway is still recognised
  /// by discovery and its row keeps its key.
  ///
  /// Returns the entry as stored.
  static Future<MGW> StorePairedMGW(MGW mgw, {MGW? replacing}) async {
    await init();
    _logger.d("$LOG_PREFIX: Store paired mgw: ${mgw.mDNSServiceName}");
    return _listLock.protect(() async {
      final storedMGWs = await LoadPairedMGWs();
      bool replaced(MGW m) =>
          isSameGateway(m, mgw) ||
          (replacing != null && isSameEntry(m, replacing));
      final at = storedMGWs.indexWhere(replaced);
      final discovered = storedMGWs
          .where((m) => replaced(m) && m.coreId.isNotEmpty)
          .firstOrNull;
      final entry = mgw.coreId.isEmpty && discovered != null
          ? MGW(discovered.hostname, discovered.mDNSServiceName,
              discovered.coreId, mgw.ip,
              networkId:
                  mgw.networkId.isEmpty ? discovered.networkId : mgw.networkId)
          : mgw;
      storedMGWs.removeWhere(replaced);
      storedMGWs.insert(at < 0 ? storedMGWs.length : at, entry);
      await _write(storedMGWs);
      return entry;
    });
  }

  /// Writes the whole list back, for updating an entry in place.
  static Future<void> ReplacePairedMGWs(List<MGW> mgws) async {
    await init();
    _logger.d("$LOG_PREFIX: Replace ${mgws.length} paired mgws");
    await _listLock.protect(() => _write(mgws));
  }

  /// Applies [change] to the list as stored now and writes it back when
  /// [change] returns true. Read and write happen under the list lock.
  static Future<bool> UpdatePairedMGWs(bool Function(List<MGW> mgws) change) async {
    await init();
    return _listLock.protect(() async {
      final mgws = await LoadPairedMGWs();
      if (!change(mgws)) return false;
      await _write(mgws);
      return true;
    });
  }

  static Future<void> _write(List<MGW> mgws) async {
    await _box?.put(_mgwConnectedKeyPrefix, json.encode(mgws));
    await _box?.flush();
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

  /// Removes the one stored entry [mgw] stands for (see [resolve]); false when
  /// none is stored any more.
  static Future<bool> RemovePairedMGW(MGW mgw) async {
    await init();
    _logger.d("$LOG_PREFIX: Remove paired mgw: ${mgw.mDNSServiceName}");
    return _listLock.protect(() async {
      final storedMGWs = await LoadPairedMGWs();
      final entry = resolve(mgw, storedMGWs);
      if (entry == null) return false;
      storedMGWs.remove(entry);
      await MgwService.ResetSessionData();
      // One credential set covers every gateway, so dropping it when the list
      // empties is the only rule available.
      if (storedMGWs.isEmpty) {
        await _clearSecrets();
      }
      await _write(storedMGWs);
      return true;
    });
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
