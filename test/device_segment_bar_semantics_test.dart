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
import 'package:mobile_app/widgets/tabs/device_tabs.dart';
import 'package:mobile_app/widgets/tabs/devices/device_list.dart';

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
      "a locked segment is announced as disabled, the current one as "
      "selected, and a locked one still toasts on tap", (tester) async {
    final semantics = tester.ensureSemantics();
    // Local mode with no cached device classes locks the Classes segment.
    await tester.runAsync(() => Settings.setLocalMode(true));
    final backend = FakeBackend();
    backend.serveJson("GET", "/device-repository/device-groups", 200, []);
    backend.serveJson("GET", "/device-repository/extended-hubs", 200, []);
    backend.serveJson("GET", "/device-repository/extended-devices", 200, []);
    serveGoldenBackend(backend);
    await warmUpMgwStorage(tester);
    await pumpGolden(tester, const DeviceTabs(),
        dark: false, size: goldenSurfaceSize);

    await tester.tap(find.text("Devices"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(DeviceList), findsOneWidget);

    // Anchored: the same words also label the Devices bar entry and tooltips.
    final all = find.semantics.byLabel(RegExp("^All\$"));
    final classes = find.semantics.byLabel(RegExp("^Classes\$"));
    expect(all, findsOneWidget);
    expect(classes, findsOneWidget);

    expect(
        classes.evaluate().single.getSemanticsData(),
        isSemantics(
            label: "Classes",
            isButton: true,
            hasEnabledState: true,
            isEnabled: false,
            hasSelectedState: true,
            isSelected: false,
            hasTapAction: true));
    expect(
        all.evaluate().single.getSemanticsData(),
        isSemantics(
            label: "All",
            isButton: true,
            hasEnabledState: true,
            isEnabled: true,
            hasSelectedState: true,
            isSelected: true,
            hasTapAction: true));

    await tester.tap(find.text("Classes"));
    await tester.pump();
    expect(toasts, contains("Currently unavailable"));

    // Screen-reader activation takes the same path as the tap.
    toasts.clear();
    tester.semantics.tap(classes);
    await tester.pump();
    expect(toasts, contains("Currently unavailable"));

    await tester.pump(const Duration(seconds: 2));
    semantics.dispose();
  });
}
