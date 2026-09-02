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
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/services/favorites_migration.dart';
import 'package:mobile_app/services/settings.dart';
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
    final secureStorageReady = _clearCorruptedSecureStorage();

    // Isar first: Auth.init's early trust of a stored identity mounts the
    // tabs, and their first loads must find the Isar cache open — otherwise
    // an offline start races past the cache and toasts backend errors. The
    // open is local and cheap; Firebase and Auth (network OIDC discovery)
    // stay parallel. _initCache needs both isar and Auth, so it runs last.
    await _timed('Isar', () async {
      isar = await IsarService().db;
    });
    await Future.wait([
      _timed('Firebase', FirebaseService.init),
      _timed('Auth', () async {
        await secureStorageReady; // corruption check must precede Auth's reads
        await Auth().init();
      }),
    ]);
    unawaited(_initCache());
  }

  static Future<void> _initLocale() async {
    await compute(AppInitializer._initIntl, Intl.systemLocale);
  }

  static Future<void> _initIntl(String locale) async {
    await initializeDateFormatting(Intl.systemLocale, null);
  }

  static Future<void> _initCache() async {
    // Before the refresh: until this has run, the cached rows are the only
    // record of the existing favorites, and a refresh replaces them.
    try {
      await FavoritesMigration.run();
    } catch (e) {
      debugPrint('Moving favorites off the cache failed: $e');
    }
    await CacheHelper.scheduleCacheUpdates().catchError(
        (Object e) => ErrorReporter.report('Could not refresh cache', e));
  }

  /// Awaits [fn], prints how long it took, and re-throws any error.
  static Future<void> _timed(String label, Future<void> Function() fn) async {
    final start = DateTime.now();
    await fn();
    debugPrint('$label init took ${DateTime.now().difference(start)}');
  }

  static Future<void> _clearCorruptedSecureStorage() async {
    if (!Platform.isAndroid) return;
    // Canary read: only reset the encrypted store when it is actually corrupted
    // (a known Android EncryptedSharedPreferences bug), instead of wiping it on
    // every launch. The unconditional wipe regenerated the encryption key and
    // logged the user out each start — ~900ms of Keystore work. A healthy read
    // here keeps the key + saved login and warms the crypto for Auth's reads.
    const canary = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );
    try {
      await canary.read(key: Auth.encKeyName);
      return; // readable → not corrupted → keep it
    } catch (e) {
      debugPrint('SecureStorage corrupted, resetting: $e');
    }
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.parent.path}/shared_prefs/FlutterSecureStorage.xml');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('SecureStorage reset failed: $e');
    }
  }
}