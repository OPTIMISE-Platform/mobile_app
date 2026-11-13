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
import 'package:mobile_app/shared/secure_storage.dart';
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
    await _timed('SecureStorageMarks',
        () => settleSecureStorageMarks(android: Platform.isAndroid));
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

  /// How long the start waits for the check's read. Past it the check runs
  /// on in the background and its finding counts when it arrives; until then
  /// the file's state is unknown ([SecureStorageHealth.unknown]).
  @visibleForTesting
  static Duration secureStorageTimeout = const Duration(seconds: 5);

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

  /// Moves the marks of the secure storage to their own box and, on Android,
  /// drops them when its file is not there, as after a restore that left the
  /// file out. Runs before anything loads the file. Never throws.
  static Future<void> settleSecureStorageMarks({required bool android}) async {
    try {
      await Settings.moveSecureStorageMarks();
      if (!android) return;
      final file = await secureStorageFile();
      if (await file.exists() || await File('${file.path}.bak').exists()) return;
      await Settings.clearSecureStorageMarks();
    } catch (e) {
      debugPrint('SecureStorage marks not settled: $e');
    }
  }

  /// Resets the Android secure storage, which holds the login, only once it
  /// is known to stay unreadable: at once for an error a retry cannot change,
  /// otherwise after [secureStorageFailureLimit] starts in a row whose read
  /// failed, as a Keystore can fail for a while. A readable start clears the
  /// count. A read slower than [secureStorageTimeout] neither counts nor
  /// resets: the start goes on and the finding is applied when it arrives.
  /// Sets [SecureStorageHealth] for the stores, which wait for it. Never
  /// throws: Auth waits on it.
  @visibleForTesting
  static Future<void> checkSecureStorage() {
    final check = _checkSecureStorage();
    SecureStorageHealth.track(check);
    return check;
  }

  static Future<void> _checkSecureStorage() async {
    try {
      if (Settings.getSecureStorageResetPending()) {
        await _deleteSecureStorageFile();
        await Settings.setSecureStorageResetPending(false);
      }
    } catch (e) {
      debugPrint('SecureStorage check failed: $e');
      return;
    }
    final probe = _probeSecureStorage();
    final _Finding finding;
    try {
      finding = await probe.timeout(secureStorageTimeout);
    } on TimeoutException {
      debugPrint('SecureStorage check runs on past its bound');
      SecureStorageHealth.unknown = true;
      unawaited(probe
          .then(_applyFinding)
          .whenComplete(() => SecureStorageHealth.unknown = false));
      return;
    }
    await _applyFinding(finding);
  }

  /// Reads the check entry, and writes it at the first start. Never throws.
  static Future<_Finding> _probeSecureStorage() async {
    final String? value;
    try {
      value = await _secureStorage.read(key: secureStorageCheckKey);
    } catch (e) {
      debugPrint('SecureStorage read failed: $e');
      if (e is PlatformException &&
          _permanentErrors.any('${e.message}\n${e.details}'.contains)) {
        return _Finding.permanent;
      }
      return _Finding.failed;
    }
    if (value != null) return _Finding.readable;
    try {
      // The plugin answers nothing for every entry when it cannot open the
      // encrypted file, as after a restore without its Keystore key.
      if (Settings.getSecureStorageCheckStored()) return _Finding.lost;
      await _secureStorage.write(key: secureStorageCheckKey, value: '1');
      await Settings.setSecureStorageCheckStored(true);
      return _Finding.readable;
    } catch (e) {
      debugPrint('SecureStorage check entry not written: $e');
      return _Finding.inconclusive;
    }
  }

  /// Never throws.
  static Future<void> _applyFinding(_Finding finding) async {
    try {
      if (finding == _Finding.inconclusive) return;
      if (finding == _Finding.readable) {
        if (Settings.getSecureStorageCheckFailures() != 0) {
          await Settings.setSecureStorageCheckFailures(0);
        }
        return;
      }
      if (finding == _Finding.permanent) {
        await _resetSecureStorage();
        return;
      }
      if (finding == _Finding.lost) SecureStorageHealth.unreadable = true;
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

  /// Bounds the reset's call to the plugin; past it the file is deleted.
  static Future<T> _bounded<T>(Future<T> call) =>
      call.timeout(secureStorageTimeout);

  /// Through the plugin, which also drops its loaded copy of the file. Its
  /// clear decrypts every entry; where that fails the file is deleted now and
  /// at the next start, as this run's loaded copy goes back with any write.
  static Future<void> _resetSecureStorage() async {
    debugPrint('SecureStorage unreadable, resetting');
    try {
      try {
        await _bounded(_secureStorage.deleteAll());
      } catch (e) {
        debugPrint('SecureStorage reset failed, deleting its file: $e');
        await Settings.setSecureStorageResetPending(true);
        await _deleteSecureStorageFile();
      }
      // Empty now, so an entry that reads as absent is absent.
      SecureStorageHealth.unreadable = false;
      await Settings.setSecureStorageCheckFailures(0);
      await Settings.setSecureStorageCheckStored(false);
      // The credentials are gone; the mark would have Auth read the empty
      // store as one that failed.
      await Settings.setCredentialsStored(false);
    } catch (e) {
      debugPrint('SecureStorage reset failed: $e');
    }
  }

  /// With the backup Android restores the file from on its next load. The
  /// login stored since the reset that deferred this goes with it.
  static Future<void> _deleteSecureStorageFile() async {
    final file = await secureStorageFile();
    for (final f in [File('${file.path}.bak'), file]) {
      if (await f.exists()) await f.delete();
    }
    await Settings.setSecureStorageCheckStored(false);
    await Settings.setCredentialsStored(false);
  }
}

/// What a read of the check entry found.
enum _Finding {
  readable,

  /// A read error that recurs on every read of the file.
  permanent,

  /// A read that failed, which a Keystore can do for a while.
  failed,

  /// The entry reads as absent although it was written.
  lost,

  /// The entry could not be written; nothing is known.
  inconclusive,
}
