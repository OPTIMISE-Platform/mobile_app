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

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/widgets/tabs/dashboard/dashboard.dart';
import 'package:mobile_app/widgets/tabs/device_tabs.dart';
import 'package:mobile_app/widgets/tabs/favorites/favorites.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

void main() {
  final toasts = <String>[];

  setUpAll(() async {
    await setUpGoldenEnvironment();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('PonnamKarthik/fluttertoast'), (call) async {
      if (call.method == "showToast") toasts.add(call.arguments["msg"]);
      return true;
    });
  });

  tearDown(() async {
    resetAppStateForGolden();
    resetGoldenBackend();
    toasts.clear();
    await Settings.setLocalMode(false);
  });

  testWidgets(
      "a locked bar entry is announced as disabled and still toasts on tap",
      (tester) async {
    final semantics = tester.ensureSemantics();
    // Local mode with no cached smart services locks Dashboard and Services.
    await tester.runAsync(() => Settings.setLocalMode(true));
    final backend = FakeBackend();
    backend.serveJson("GET", "/device-repository/device-groups", 200, []);
    backend.serveJson("GET", "/device-repository/extended-hubs", 200, []);
    backend.serveJson("GET", "/device-repository/extended-devices", 200, []);
    serveGoldenBackend(backend);
    await warmUpMgwStorage(tester);
    await pumpGolden(tester, const DeviceTabs(),
        dark: false, size: goldenSurfaceSize);

    expect(
        tester.getSemantics(find.text("Dashboard")),
        isSemantics(
            hasEnabledState: true,
            isEnabled: false,
            isButton: true,
            hasTapAction: true));
    expect(tester.getSemantics(find.text("Favorites")),
        isSemantics(hasEnabledState: true, isEnabled: true));

    await tester.tap(find.text("Dashboard"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(Dashboard), findsNothing);
    expect(find.byType(DeviceListFavorites), findsOneWidget);
    expect(toasts, contains("Currently unavailable"));

    // Screen-reader activation takes the same path as the tap.
    toasts.clear();
    tester.semantics.tap(find.semantics.byLabel(RegExp("^Services")));
    await tester.pump();
    expect(toasts, contains("Currently unavailable"));

    await tester.pump(const Duration(seconds: 2));
    semantics.dispose();
  });
}
