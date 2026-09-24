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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/mgw/storage.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/display_time.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/shared/http_client_adapter.dart';
import 'package:mobile_app/theme.dart' show MyTheme;
import 'package:mobile_app/widgets/tabs/nav.dart';
import 'package:provider/provider.dart';

import 'fake_backend.dart';
import 'test_helper.dart';

/// Phone-sized surface at devicePixelRatio 1, so the golden PNGs stay small.
const goldenSurfaceSize = Size(412, 915);

bool _fontsLoaded = false;

/// Everything a golden test file needs once, in `setUpAll`, before any
/// service class, `Auth()` or `AppState()` is touched: those read their
/// endpoints and configuration from Settings/dotenv on first access.
Future<void> setUpGoldenEnvironment() async {
  setUpTestEnvironment();
  if (!dotenv.isInitialized) {
    dotenv.loadFromString(
        envString: await File(".env.example").readAsString());
  }
  await Settings.init();
  FlutterSecureStorage.setMockInitialValues({});
  ErrorReporter.present = (_) {};
  await _loadTestFonts();
  _mockFluttertoast();
  // Every golden renders display timestamps in UTC, not just the ones that
  // also call serveGoldenBackend: a screen with no backend of its own (e.g.
  // NotificationList, fed straight from AppState) still calls toDisplayTime,
  // and left on .toLocal() its goldens depend on the machine's time zone.
  useUtcForDisplayTime = true;
}

/// Several widgets call `Toast.showToastNoContext` directly, which reaches the
/// real `fluttertoast` plugin - unhandled in a test, that throws
/// MissingPluginException. The channel and method name are the package's own
/// (`fluttertoast-9.1.0/lib/fluttertoast.dart`); the handler's return value is
/// unused by the call sites.
void _mockFluttertoast() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('PonnamKarthik/fluttertoast'),
          (call) async => true);
}

/// Backend seam for golden tests that fetch data: every Dio adapter reads
/// from [backend] and `Auth().getHeaders()` is short-circuited. Call
/// [resetGoldenBackend] in `tearDown`. (The UTC display-time switch lives in
/// [setUpGoldenEnvironment] instead - screens with no backend of their own
/// still need it.)
void serveGoldenBackend(FakeBackend backend,
    {Map<String, String> headers = const {"authorization": "Bearer t"}}) {
  AppHttpClientAdapter.testOverride = backend;
  Auth.headersOverride = () async => headers;
}

/// Undoes [serveGoldenBackend].
void resetGoldenBackend() {
  AppHttpClientAdapter.testOverride = null;
  Auth.headersOverride = null;
}

/// `MgwStorage`'s first call opens a Hive box via path_provider, which - like
/// the Hive writes in [pumpGolden]'s own doc comment - never resolves inside
/// testWidgets' fake-async zone; call this once, before pumping, for any
/// golden that reaches `AppState.init()` or `AppState.loadNetworks()`, both of
/// which read paired gateways through it.
Future<void> warmUpMgwStorage(WidgetTester tester) =>
    tester.runAsync(() => MgwStorage.init());

/// Registers the fonts `flutter test` does not load by default (it renders
/// text as Ahem boxes otherwise), from the SDK the test is running under.
Future<void> _loadTestFonts() async {
  if (_fontsLoaded) return;
  final flutterRoot = Platform.environment["FLUTTER_ROOT"];
  if (flutterRoot == null || flutterRoot.isEmpty) {
    throw StateError(
        "FLUTTER_ROOT is not set - golden tests need it to find the SDK's "
        "bundled Roboto/MaterialIcons fonts. Run this via `flutter test`.");
  }
  final fontsDir = "$flutterRoot/bin/cache/artifacts/material_fonts";
  await _loadFont("Roboto", [
    "$fontsDir/Roboto-Regular.ttf",
    "$fontsDir/Roboto-Medium.ttf",
    "$fontsDir/Roboto-Bold.ttf",
  ]);
  await _loadFont("MaterialIcons", ["$fontsDir/MaterialIcons-Regular.otf"]);
  _fontsLoaded = true;
}

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) {
      throw StateError("Font file missing: $path");
    }
    loader.addFont(file.readAsBytes().then((bytes) => ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

/// Wraps [home] the way `main.dart` wraps the app, at the fixed golden
/// surface size, and pumps it.
///
/// Uses `.value`, not `create:`: `create:` would dispose the [AppState] and
/// [Auth] singletons when the widget tree is torn down at the end of the
/// test, breaking every golden test that runs after it in the same file.
///
/// [settle] advances time by a fixed duration instead of calling
/// `pumpAndSettle`, which can hang: several screens under test carry a
/// `DelayedCircularProgressIndicator` or the app bar's repeating update icon,
/// both endless animations while nothing stops them.
///
/// [size] overrides the surface for a non-golden test that needs a specific
/// width, e.g. checking layout at a narrower phone size.
Future<void> pumpGolden(
  WidgetTester tester,
  Widget home, {
  required bool dark,
  Duration settle = const Duration(milliseconds: 300),
  Size size = goldenSurfaceSize,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });

  // A fresh mount per variant: switching the theme of a mounted app
  // cross-fades it, and the fixed [settle] would capture that half done.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: AppState()),
        ChangeNotifierProvider.value(value: Auth()),
      ],
      child: MaterialApp(
        theme: MyTheme.materialTheme,
        darkTheme: MyTheme.materialDarkTheme,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        debugShowCheckedModeBanner: false,
        home: home,
      ),
    ),
  );
  await tester.pump(settle);
}

/// Resets the parts of [AppState] a golden test may have filled, so the next
/// test in the file starts from a clean slate. `nav.dart`'s `navItems` is
/// module-level and not owned by [AppState], so its `disabled` flags are
/// reset here too.
void resetAppStateForGolden() {
  AppState().clearDeviceData();
  AppState().clearNetworkData();
  AppState().clearData();
  for (final item in navItems) {
    item.disabled = false;
  }
}
