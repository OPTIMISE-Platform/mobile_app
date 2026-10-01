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

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/services/mgw/auth_service.dart';
import 'package:mobile_app/services/mgw/gateway_host.dart';
import 'package:mobile_app/services/mgw/restricted.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mutex/mutex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

const LOG_PREFIX = "MGW-STORAGE-SERVICE";

/// No device credentials are stored, as opposed to a store that failed to read.
class MgwCredentialsMissing implements Exception {
  @override
  String toString() => "No pairing credentials are stored";
}

/// Persistence for gateway pairing.
///
/// Each stored entry has its own device secret and session, kept in the
/// encrypted store under the entry's pairing id; the list of paired gateways
/// lives in the plain Hive box. The secret mints session tokens and does not
/// expire, so it is worth more to an attacker than a session token.
class MgwStorage {
  // Was a Hive key until 0.0.386. Still read once so an existing pairing
  // survives the move, then deleted from the plaintext box.
  static const _mgwCredentialsKeyPrefix = "credentials_";

  static const _mgwConnectedKeyPrefix = "connected_mgws_";

  // The one credential set every gateway shared before pairings had their own.
  // Copied to the entries once, then deleted.
  static const _sharedCredentialsKey = "mgw-device-credentials";

  /// Secure-storage key of the device credentials of [pairingId].
  static String credentialsKeyOf(String pairingId) =>
      "$_sharedCredentialsKey:$pairingId";

  // The basic-auth path was removed with the old, port-based gateway
  // generation. These two keys are kept only so init() can delete any
  // leftover password instead of leaving it on the device.
  static const _basicAuthKey = "mgw-basic-auth-password";
  static const _mgwBasicAuthCredentialsKeyPrefix = "basic_auth_credentials_";

  static const _boxName = "mgw.box";
  static Box<String>? _box;

  // Every change to the gateway list reads and writes the whole list, so two
  // unserialized changes (a pairing during an address refresh) lose one. The
  // per-pairing secrets are written under it too, so the migration of the
  // shared set cannot overwrite credentials a pairing stored meanwhile.
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

  /// The migration of the shared secrets in this run of the app, started by
  /// the first credential read. It runs once per start and never fails; a
  /// failure is kept in [_migrationFailure] and retried on the next start.
  static Future<void>? _migration;
  static (Object, StackTrace)? _migrationFailure;

  /// Forgets that the shared secrets were migrated, as a new start would.
  @visibleForTesting
  static void restartForTest() {
    _migration = null;
    _migrationFailure = null;
  }

  /// Called before every write of the gateway list; a test throws from it to
  /// make the write fail.
  @visibleForTesting
  static void Function()? beforeListWriteForTest;

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

  static String _newPairingId() => const Uuid().v4();

  /// Stores [user] as the credentials of [pairingId].
  static Future<void> StoreCredentials(
      String pairingId, DeviceUserCredentials user) async {
    await init();
    await _listLock.protect(() => _writeCredentials(pairingId, user));
  }

  static Future<void> _writeCredentials(
      String pairingId, DeviceUserCredentials user) async {
    if (pairingId.isEmpty) {
      throw ArgumentError.value(pairingId, "pairingId", "must not be empty");
    }
    _logger.d("$LOG_PREFIX: Store mgw device credentials");
    await _secure.write(
        key: credentialsKeyOf(pairingId), value: json.encode(user));
  }

  /// The credentials of [pairingId]. Throws [MgwCredentialsMissing] when none
  /// are stored, and the storage's own error when they could not be read.
  static Future<DeviceUserCredentials> LoadCredentials(String pairingId) async {
    await init();
    _logger.d("$LOG_PREFIX: Load mgw device credentials");
    final migration = _migration ??= _migrate();
    // Credentials of its own are never touched by the migration, so a pairing
    // that has them does not wait for it.
    final own = await _readCredentials(pairingId);
    if (own != null) return own;
    await migration;
    final copied = await _readCredentials(pairingId);
    if (copied != null) return copied;
    // Not missing: the shared set may still be waiting to be copied here.
    final failure = _migrationFailure;
    if (failure != null) Error.throwWithStackTrace(failure.$1, failure.$2);
    throw MgwCredentialsMissing();
  }

  static Future<DeviceUserCredentials?> _readCredentials(
      String pairingId) async {
    if (pairingId.isEmpty) return null;
    final stored = await _secure.read(key: credentialsKeyOf(pairingId));
    return stored == null
        ? null
        : DeviceUserCredentials.fromJson(json.decode(stored));
  }

  static Future<void> _migrate() async {
    try {
      await _listLock.protect(_migrateSharedSecrets);
    } catch (e, s) {
      _migrationFailure = (e, s);
      ErrorReporter.log(
          "Could not move the shared gateway credentials to the pairings",
          e,
          s);
    }
  }

  /// Copies the credential set and session all gateways used to share to every
  /// entry without credentials of its own, then deletes the shared keys.
  ///
  /// Under the list lock. A failure leaves the shared keys in place, so the
  /// next start copies to the entries still without credentials; an entry's
  /// session is copied before its credentials, so one that has credentials is
  /// done.
  static Future<void> _migrateSharedSecrets() async {
    final credentials = await _secure.read(key: _sharedCredentialsKey) ??
        _box?.get(_mgwCredentialsKeyPrefix);
    final session = await _secure.read(key: MgwService.sharedSessionKey);
    final expiration =
        await _secure.read(key: MgwService.sharedSessionExpirationKey);
    if (credentials == null && session == null && expiration == null) return;

    if (credentials != null) {
      var copied = 0;
      for (final mgw in await _loadLocked()) {
        final key = credentialsKeyOf(mgw.pairingId);
        if (await _secure.read(key: key) != null) continue;
        if (session != null && expiration != null) {
          await _secure.write(
              key: MgwService.sessionKeyOf(mgw.pairingId), value: session);
          await _secure.write(
              key: MgwService.sessionExpirationKeyOf(mgw.pairingId),
              value: expiration);
        }
        await _secure.write(key: key, value: credentials);
        copied++;
      }
      _logger.i("$LOG_PREFIX: Copied the shared credentials to $copied "
          "pairings");
    }
    await _clearSharedSecrets();
  }

  /// Whether [a] and [b] carry the same pairing id.
  static bool isSamePairing(MGW a, MGW b) =>
      a.pairingId.isNotEmpty && a.pairingId == b.pairingId;

  /// Whether [a] and [b] are the same gateway: the pairing or the core id
  /// decides when both carry one, otherwise the hostname or the address,
  /// unless both are bound to different networks.
  static bool isSameGateway(MGW a, MGW b) {
    if (isSamePairing(a, b)) return true;
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

  /// Whether [a] and [b] are the same stored entry, field for field. A pairing
  /// id counts only when both carry one, so a copy made before the entry was
  /// stored still matches.
  static bool isSameEntry(MGW a, MGW b) =>
      a.hostname == b.hostname &&
      a.ip == b.ip &&
      a.coreId == b.coreId &&
      a.networkId == b.networkId &&
      (a.pairingId.isEmpty ||
          b.pairingId.isEmpty ||
          a.pairingId == b.pairingId);

  /// The entry in [stored] that [mgw], a possibly older copy, stands for.
  ///
  /// The pairing id decides when an entry carries it. Otherwise matched on
  /// what does not change while paired: the core id, or the hostname and
  /// network without one. The address does not count, as the address refresh
  /// rewrites it. Among several matches the field-exact one wins, then the one
  /// bound to the same network.
  static MGW? resolve(MGW mgw, List<MGW> stored) {
    final paired = stored.where((m) => isSamePairing(m, mgw)).firstOrNull;
    if (paired != null) return paired;
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
  /// The entry keeps the pairing id of [mgw], else of [replacing], else of the
  /// first entry it replaces; only a gateway not stored yet gets a new one.
  /// The secrets of a replaced entry with another pairing id are dropped.
  ///
  /// [credentials] are stored under the entry's pairing id in the same step,
  /// with the session of the credentials they replace dropped; if the list
  /// cannot be written, credentials stored under a new id are dropped again.
  ///
  /// An entry added by address carries no core id or mDNS name; replacing a
  /// discovered entry with it keeps those, so the gateway is still recognised
  /// by discovery and its row keeps its key.
  ///
  /// Returns the entry as stored.
  static Future<MGW> StorePairedMGW(MGW mgw,
      {MGW? replacing, DeviceUserCredentials? credentials}) async {
    await init();
    _logger.d("$LOG_PREFIX: Store paired mgw: ${mgw.mDNSServiceName}");
    return _listLock.protect(() async {
      final storedMGWs = await _loadLocked();
      bool isReplacing(MGW m) =>
          replacing != null &&
          (isSamePairing(m, replacing) || isSameEntry(m, replacing));
      final pairingId = mgw.pairingId.isNotEmpty
          ? mgw.pairingId
          : (storedMGWs.where(isReplacing).firstOrNull ??
                      storedMGWs.where((m) => isSameGateway(m, mgw)).firstOrNull)
                  ?.pairingId ??
              _newPairingId();
      bool replaced(MGW m) =>
          m.pairingId == pairingId || isSameGateway(m, mgw) || isReplacing(m);

      final isNewPairing = !storedMGWs.any((m) => m.pairingId == pairingId);
      final at = storedMGWs.indexWhere(replaced);
      final discovered = storedMGWs
          .where((m) => replaced(m) && m.coreId.isNotEmpty)
          .firstOrNull;
      final entry = mgw.coreId.isEmpty && discovered != null
          ? MGW(discovered.hostname, discovered.mDNSServiceName,
              discovered.coreId, mgw.ip,
              networkId:
                  mgw.networkId.isEmpty ? discovered.networkId : mgw.networkId,
              pairingId: pairingId)
          : MGW(mgw.hostname, mgw.mDNSServiceName, mgw.coreId, mgw.ip,
              networkId: mgw.networkId, pairingId: pairingId);
      final dropped = {
        for (final m in storedMGWs)
          if (replaced(m) && m.pairingId != pairingId) m.pairingId
      };
      storedMGWs.removeWhere(replaced);
      dropped.removeWhere((id) => storedMGWs.any((m) => m.pairingId == id));
      storedMGWs.insert(at < 0 ? storedMGWs.length : at, entry);

      if (credentials != null) {
        try {
          await _writeCredentials(pairingId, credentials);
        } catch (_) {
          if (isNewPairing) await _dropSecretsQuietly(pairingId);
          rethrow;
        }
        // The stored session belongs to the credentials just replaced.
        await MgwService.ResetSessionData(pairingId);
      }
      try {
        await _write(storedMGWs);
      } catch (_) {
        // No entry would carry the id, so nothing would read or remove them.
        if (credentials != null && isNewPairing) {
          await _dropSecretsQuietly(pairingId);
        }
        rethrow;
      }
      for (final id in dropped) {
        await _dropSecretsQuietly(id);
      }
      return entry;
    });
  }

  /// Writes the whole list back, for updating an entry in place. Entries
  /// without a pairing id get one, on the instances passed.
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
      final mgws = await _loadLocked();
      if (!change(mgws)) return false;
      await _write(mgws);
      return true;
    });
  }

  static Future<void> _write(List<MGW> mgws) async {
    beforeListWriteForTest?.call();
    _assignPairingIds(mgws);
    await _box?.put(_mgwConnectedKeyPrefix, json.encode(mgws));
    await _box?.flush();
  }

  static bool _assignPairingIds(List<MGW> mgws) {
    var assigned = false;
    for (final mgw in mgws) {
      if (mgw.pairingId.isNotEmpty) continue;
      mgw.pairingId = _newPairingId();
      assigned = true;
    }
    return assigned;
  }

  static List<MGW> _read() {
    final encodedMgws = _box?.get(_mgwConnectedKeyPrefix);
    if (encodedMgws == null) return [];
    return [for (final mgw in jsonDecode(encodedMgws)) MGW.fromJson(mgw)];
  }

  /// The stored list, after giving entries stored without a pairing id one and
  /// writing them back. Only under the list lock.
  static Future<List<MGW>> _loadLocked() async {
    final mgws = _read();
    if (_assignPairingIds(mgws)) await _write(mgws);
    return mgws;
  }

  static Future<List<MGW>> LoadPairedMGWs() async {
    await init();
    _logger.d("$LOG_PREFIX: Load paired mgws");
    final mgws = _read();
    if (mgws.every((m) => m.pairingId.isNotEmpty)) return mgws;
    return _listLock.protect(_loadLocked);
  }

  /// Removes the one stored entry [mgw] stands for (see [resolve]) and its
  /// secrets; false when none is stored any more.
  static Future<bool> RemovePairedMGW(MGW mgw) async {
    await init();
    _logger.d("$LOG_PREFIX: Remove paired mgw: ${mgw.mDNSServiceName}");
    return _listLock.protect(() async {
      final storedMGWs = await _loadLocked();
      final entry = resolve(mgw, storedMGWs);
      if (entry == null) return false;
      storedMGWs.remove(entry);
      // Before the list is written: a failed delete keeps the entry, so the
      // removal can be tried again instead of leaving its secret behind.
      if (!storedMGWs.any((m) => m.pairingId == entry.pairingId)) {
        await _secure.delete(key: credentialsKeyOf(entry.pairingId));
        await MgwService.ResetSessionData(entry.pairingId);
      }
      if (storedMGWs.isEmpty) await _clearSharedSecrets();
      await _write(storedMGWs);
      return true;
    });
  }

  /// Never throws: it cleans up after a change that already succeeded or
  /// failed for another reason.
  static Future<void> _dropSecretsQuietly(String pairingId) async {
    try {
      await _secure.delete(key: credentialsKeyOf(pairingId));
    } catch (e, s) {
      ErrorReporter.log("Could not drop the credentials of a gateway pairing", e, s);
    }
    await MgwService.ResetSessionData(pairingId);
  }

  static Future<void> _clearSharedSecrets() async {
    _logger.d("$LOG_PREFIX: Clear shared mgw secrets");
    await _secure.delete(key: _sharedCredentialsKey);
    await _secure.delete(key: _basicAuthKey);
    await _box?.delete(_mgwCredentialsKeyPrefix);
    await _box?.delete(_mgwBasicAuthCredentialsKeyPrefix);
    await _box?.flush();
    await _secure.delete(key: MgwService.sharedSessionKey);
    await _secure.delete(key: MgwService.sharedSessionExpirationKey);
  }
}
