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

/// Runs all one-time app initialisation steps in sequence and prints
/// individual timing information to the debug console.
class AppInitializer {
  AppInitializer._(); // static-only class

  static Future<void> run() async {
    final appStart = DateTime.now();

    // Must be first — plugins require the binding before any I/O.
    WidgetsFlutterBinding.ensureInitialized();

    await _timed('dotenv', () => dotenv.load(fileName: '.env'));
    await _timed('Settings', () async => await Settings.init());
    await _timed('MyTheme', () async => await MyTheme.loadTheme());
    await _timed('findSystemLocale', findSystemLocale);
    await _timed(
      'initializeDateFormatting',
          () => initializeDateFormatting(Intl.systemLocale, null),
    );
    debugPrint('App init took ${DateTime.now().difference(appStart)}');
  }

  static Future<void> runDeferred() async {
    await _timed('Isar', () async {
      isar = kIsWeb ? null : await IsarService().db;
    });
    await _timed('Firebase', FirebaseService.init);
    await _timed('Auth', () => Auth().init());
    await _timed('Cache', _initCache);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

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
}