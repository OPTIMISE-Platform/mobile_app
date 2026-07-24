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
import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import "package:intl/intl_standalone.dart"
if (dart.library.html) "package:intl/intl_browser.dart";
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/isar.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/toast.dart';
import 'package:mobile_app/firebase_service.dart';
import 'package:path_provider/path_provider.dart';


class AppInitializer {
  AppInitializer._();

  static Future<void> run() async {
    final appStart = DateTime.now();

    await _clearCorruptedSecureStorage();

    await _timed('dotenv', () => dotenv.load(fileName: '.env'));
    await _timed('Settings', () async => await Settings.init());
    await _timed('MyTheme', () async => await MyTheme.loadTheme());
    unawaited(_initLocale());
    debugPrint('App init took ${DateTime.now().difference(appStart)}');
  }

  static Future<void> runDeferred() async {
    // Isar (local DB), Firebase and Auth (network OIDC discovery) are mutually
    // independent — run them in parallel so the login gate isn't blocked behind
    // the sum of their latencies. _initCache needs both isar and Auth, so it
    // runs afterwards.
    await Future.wait([
      _timed('Isar', () async {
        isar = kIsWeb ? null : await IsarService().db;
      }),
      _timed('Firebase', FirebaseService.init),
      _timed('Auth', () => Auth().init()),
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
    await CacheHelper.scheduleCacheUpdates()
        .catchError((_) => Toast.showToastNoContext('Could not refresh cache'));
  }

  /// Awaits [fn], prints how long it took, and re-throws any error.
  static Future<void> _timed(String label, Future<void> Function() fn) async {
    final start = DateTime.now();
    await fn();
    debugPrint('$label init took ${DateTime.now().difference(start)}');
  }

  static Future<void> _clearCorruptedSecureStorage() async {
    if (!Platform.isAndroid) return;
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