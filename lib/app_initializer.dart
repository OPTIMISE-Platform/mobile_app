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

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:isar_community/isar.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/app_version.dart';
import 'package:mobile_app/shared/isar.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/firebase_service.dart';
import 'package:path_provider/path_provider.dart';


class AppInitializer {
  AppInitializer._();

  static Future<void> run() async {
    final appStart = DateTime.now();

    await _timed('dotenv', () => dotenv.load(fileName: '.env'));
    await _timed('AppVersion', AppVersion.init);
    await _timed('Settings', () async => await Settings.init());
    await _timed('MyTheme', () async => await MyTheme.loadTheme());
    unawaited(_initLocale());
    debugPrint('App init took ${DateTime.now().difference(appStart)}');
  }

  static Future<void> runDeferred() async {
    // The secure-storage corruption check triggers the one-time (~700ms) Android
    // EncryptedSharedPreferences crypto init, so it lives here (deferred, behind
    // the first frame) rather than in run(). Start it now but only Auth waits on
    // it — Isar/Firebase don't touch secure storage, so they overlap it freely.
    final secureStorageReady =
        Platform.isAndroid ? checkSecureStorage() : Future<void>.value();

    // Isar first: Auth.init's early trust of a stored identity mounts the
    // tabs, and their first loads must find the Isar cache open — otherwise
    // an offline start races past the cache and toasts backend errors. The
    // open is local and cheap; Firebase and Auth (network OIDC discovery)
    // stay parallel. _initCache needs both isar and Auth, so it runs last.
    await openCache();
    await Future.wait([
      _timed('Firebase', FirebaseService.init),
      _timed('Auth', () async {
        await secureStorageReady; // corruption check must precede Auth's reads
        await Auth().init();
      }),
    ]);
    unawaited(_initCache());
  }

  /// Opens Isar ([open] stands in for it in tests), then retries a pending
  /// account wipe before the tabs can mount on a stored identity: a switch
  /// that did not complete left the previous account's rows behind.
  @visibleForTesting
  static Future<void> openCache([Future<Isar?> Function()? open]) async {
    await _timed('Isar', () async {
      isar = await (open ?? () => IsarService().db)();
    });
    await CacheHelper.retryPendingAccountWipe();
  }

  static Future<void> _initLocale() async {
    await compute(AppInitializer._initIntl, Intl.systemLocale);
  }

  static Future<void> _initIntl(String locale) async {
    await initializeDateFormatting(Intl.systemLocale, null);
  }

  /// The favorites migration runs inside [CacheHelper.scheduleCacheUpdates],
  /// ahead of any refresh, which the resume path needs as well.
  static Future<void> _initCache() async {
    await CacheHelper.scheduleCacheUpdates().catchError((Object e, StackTrace s) =>
        ErrorReporter.log('Could not refresh cache', e, s));
  }

  /// Awaits [fn], prints how long it took, and re-throws any error.
  static Future<void> _timed(String label, Future<void> Function() fn) async {
    final start = DateTime.now();
    await fn();
    debugPrint('$label init took ${DateTime.now().difference(start)}');
  }

  /// The entry [checkSecureStorage] reads; nothing else uses it.
  static const secureStorageCheckKey = 'secure_storage_check';

  /// Starts in a row whose check failed, after which the store is reset.
  static const secureStorageFailureLimit = 3;

  /// On Android flutter_secure_storage keeps every store in this one file.
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Messages of errors that recur on every read of the same file, found in
  /// the Java stack trace the plugin sends as the details: a key or value that
  /// does not match the keyset, or a Keystore key that is gone for good.
  static const _permanentErrors = [
    'Could not decrypt value',
    'Could not decrypt key',
    'Could not encrypt key',
    'AEADBadTagException',
    'KeyPermanentlyInvalidatedException',
  ];

  /// The file of the Android secure storage.
  @visibleForTesting
  static Future<File> Function() secureStorageFile = () async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.parent.path}/shared_prefs/FlutterSecureStorage.xml');
  };

  /// Resets the Android secure storage, which holds the login, only once it
  /// is known to stay unreadable: at once for an error a retry cannot change,
  /// otherwise after [secureStorageFailureLimit] starts in a row whose read
  /// failed, as a Keystore can fail for a while. A readable start clears the
  /// count. Never throws: Auth waits on it.
  @visibleForTesting
  static Future<void> checkSecureStorage() async {
    try {
      if (Settings.getSecureStorageResetPending()) {
        await _deleteSecureStorageFile();
        await Settings.setSecureStorageResetPending(false);
      }
      if (await _secureStorageReadable()) {
        if (Settings.getSecureStorageCheckFailures() != 0) {
          await Settings.setSecureStorageCheckFailures(0);
        }
        return;
      }
    } on _PermanentStorageError {
      return _resetSecureStorage();
    } catch (e) {
      debugPrint('SecureStorage check failed: $e');
      return;
    }
    try {
      final failures = Settings.getSecureStorageCheckFailures() + 1;
      if (failures < secureStorageFailureLimit) {
        await Settings.setSecureStorageCheckFailures(failures);
        return;
      }
    } catch (e) {
      debugPrint('SecureStorage check failed: $e');
      return;
    }
    await _resetSecureStorage();
  }

  /// False for a read that failed, also for the check entry reading as absent
  /// once written: the plugin answers nothing for every entry when it cannot
  /// open the encrypted file, as after a restore without its Keystore key.
  static Future<bool> _secureStorageReadable() async {
    final String? value;
    try {
      value = await _secureStorage.read(key: secureStorageCheckKey);
    } catch (e) {
      debugPrint('SecureStorage read failed: $e');
      if (e is PlatformException &&
          _permanentErrors.any('${e.message}\n${e.details}'.contains)) {
        throw _PermanentStorageError();
      }
      return false;
    }
    if (value != null) return true;
    if (Settings.getSecureStorageCheckStored()) return false;
    await _secureStorage.write(key: secureStorageCheckKey, value: '1');
    await Settings.setSecureStorageCheckStored(true);
    return true;
  }

  /// Through the plugin, which also drops its loaded copy of the file. Its
  /// clear decrypts every entry; where that fails the file is deleted now and
  /// at the next start, as this run's loaded copy goes back with any write.
  static Future<void> _resetSecureStorage() async {
    debugPrint('SecureStorage unreadable, resetting');
    try {
      try {
        await _secureStorage.deleteAll();
      } catch (e) {
        debugPrint('SecureStorage reset failed, deleting its file: $e');
        await Settings.setSecureStorageResetPending(true);
        await _deleteSecureStorageFile();
      }
      await Settings.setSecureStorageCheckFailures(0);
      await Settings.setSecureStorageCheckStored(false);
      // The credentials are gone; the mark would have Auth read the empty
      // store as one that failed.
      await Settings.setCredentialsStored(false);
    } catch (e) {
      debugPrint('SecureStorage reset failed: $e');
    }
  }

  /// With the backup Android restores the file from on its next load.
  static Future<void> _deleteSecureStorageFile() async {
    final file = await secureStorageFile();
    for (final f in [File('${file.path}.bak'), file]) {
      if (await f.exists()) await f.delete();
    }
    await Settings.setSecureStorageCheckStored(false);
  }
}

/// A read error that recurs on every read of the secure storage's file.
class _PermanentStorageError implements Exception {}
