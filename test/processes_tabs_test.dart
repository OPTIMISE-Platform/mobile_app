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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/widgets/tabs/device_tabs.dart';
import 'package:mobile_app/widgets/tabs/nav.dart';
import 'package:mobile_app/widgets/tabs/processes/processes_list.dart';
import 'package:mobile_app/widgets/tabs/smart-services/instances.dart';

import 'golden_helper.dart';
import 'process_backend.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() async {
    resetAppStateForGolden();
    resetGoldenBackend();
    await Settings.setInitialTab(tabFavorites);
  });

  test("Processes belongs to the Services bar tab, not to the bar itself", () {
    expect(barTabForView(tabProcesses), tabSmartServices);
    expect(barTabForView(tabSmartServices), tabSmartServices);
    expect(navBarTabs, isNot(contains(tabProcesses)));
    expect(segmentsForView(tabProcesses), serviceSegmentTabs);
    expect(segmentsForView(tabSmartServices), serviceSegmentTabs);
    expect(segmentsForView(tabSensors), isNull);
  });

  testWidgets(
      "Services opens a segment bar; the FAB belongs to Smart Services only",
      (tester) async {
    final backend = ProcessBackend(
      deployments: [deploymentJson("d1", "Heating")],
      instances: [],
    );
    backend.serveJson("GET", "/device-repository/device-groups", 200, []);
    backend.serveJson("GET", "/device-repository/extended-hubs", 200, []);
    backend.serveJson("GET", "/device-repository/extended-devices", 200, []);
    backend.serveJson("GET", "/smart-services/repository/instances", 200, []);
    serveGoldenBackend(backend);
    await warmUpMgwStorage(tester);
    await pumpGolden(tester, const DeviceTabs(),
        dark: false, size: goldenSurfaceSize);

    Future<void> settle() async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    expect(find.text("Smart Services"), findsNothing);

    await tester.tap(find.text("Services"));
    await settle();
    expect(find.byType(SmartServicesInstances), findsOneWidget);
    expect(find.text("Smart Services"), findsOneWidget);
    expect(find.text("Processes"), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    await tester.tap(find.text("Processes"));
    await settle();
    expect(find.byType(ProcessesList), findsOneWidget);
    expect(find.byType(SmartServicesInstances), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.text("Heating"), findsOneWidget);
    // The Services bar tab stays selected while a segment is shown.
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, navBarTabs.indexOf(tabSmartServices));

    await tester.tap(find.text("Smart Services"));
    await settle();
    expect(find.byType(SmartServicesInstances), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });
}
