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
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_class.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/widgets/tabs/classes/device_class.dart';
import 'package:mobile_app/widgets/tabs/dashboard/dashboard.dart';
import 'package:mobile_app/widgets/tabs/device_tabs.dart';
import 'package:mobile_app/widgets/tabs/devices/device_list.dart';
import 'package:mobile_app/widgets/tabs/favorites/favorites.dart';
import 'package:mobile_app/widgets/tabs/groups/group_list.dart';
import 'package:mobile_app/widgets/tabs/nav.dart';
import 'package:mobile_app/widgets/tabs/sensors/sensor_values.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

void main() {
  // Records every call reaching the fluttertoast channel, so a disabled tap
  // can be checked for the toast it requests, not just for not navigating.
  final toastCalls = <MethodCall>[];

  setUpAll(() async {
    await setUpGoldenEnvironment();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('PonnamKarthik/fluttertoast'), (call) async {
      toastCalls.add(call);
      return true;
    });
  });

  tearDown(() async {
    resetAppStateForGolden();
    resetGoldenBackend();
    toastCalls.clear();
    await Settings.setInitialTab(tabFavorites);
    await Settings.setLocalMode(false);
  });

  // Same empty-everywhere backend as golden_device_tabs_shell_test.dart: the
  // shell's didChangeDependencies loads device groups and networks
  // regardless of which tab a test starts on.
  FakeBackend emptyBackend() {
    final backend = FakeBackend();
    backend.serveJson("GET", "/device-repository/device-groups", 200, []);
    backend.serveJson("GET", "/device-repository/extended-hubs", 200, []);
    backend.serveJson("GET", "/device-repository/extended-devices", 200, []);
    return backend;
  }

  Future<void> pumpShell(WidgetTester tester, {Size? size}) async {
    serveGoldenBackend(emptyBackend());
    await warmUpMgwStorage(tester);
    await pumpGolden(tester, const DeviceTabs(),
        dark: false, size: size ?? goldenSurfaceSize);
  }

  bool toastedUnavailable() =>
      toastCalls.any((c) => c.method == "showToast" && c.arguments["msg"] == "Currently unavailable");

  testWidgets("tapping a bar tab switches view", (tester) async {
    await pumpShell(tester);
    expect(find.byType(DeviceListFavorites), findsOneWidget);

    await tester.tap(find.text("Sensors"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(SensorValues), findsOneWidget);
    expect(find.byType(DeviceListFavorites), findsNothing);
  });

  testWidgets(
      "leaving a drill-down via a bar switch clears its search override",
      (tester) async {
    final deviceClass = DeviceClass("class-1", "Lamps", "");
    AppState().deviceClasses[deviceClass.id] = deviceClass;
    await pumpShell(tester);

    await tester.tap(find.text("Devices"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text("Classes"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text(deviceClass.name));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // The drill-down forces the search icon on over Classes' own hideSearch.
    expect(find.byIcon(Icons.search), findsOneWidget);

    // Leaving via a different bar tab, not the drill-down's own back arrow.
    await tester.tap(find.text("Sensors"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Sensors hides search - the override must not have survived the switch.
    expect(find.byIcon(Icons.search), findsNothing);
  });

  testWidgets("tapping the active tab from a drill-down returns to root",
      (tester) async {
    final deviceClass = DeviceClass("class-1", "Lamps", "");
    AppState().deviceClasses[deviceClass.id] = deviceClass;
    await pumpShell(tester);

    await tester.tap(find.text("Devices"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text("Classes"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(DeviceListByDeviceClass), findsOneWidget);

    // Drill into the class - opens in place, via customAppBarTitle/
    // onBackCallback, not a page push.
    await tester.tap(find.text(deviceClass.name));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);

    // Devices is already the active bar tab (Classes is one of its
    // segments) - tapping it again has to leave the drill-down, not reload.
    await tester.tap(find.text("Devices"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byIcon(Icons.arrow_back), findsNothing);
    // Back at the Classes segment's own root, not reset to "All".
    expect(find.byType(DeviceListByDeviceClass), findsOneWidget);
  });

  testWidgets(
      "re-tapping the active segment from a drill-down returns to that segment's root",
      (tester) async {
    final deviceClass = DeviceClass("class-1", "Lamps", "");
    AppState().deviceClasses[deviceClass.id] = deviceClass;
    await pumpShell(tester);

    await tester.tap(find.text("Devices"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text("Classes"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text(deviceClass.name));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);

    // The Classes segment tab itself, not the main Devices bar tab.
    await tester.tap(find.text("Classes"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(find.byType(DeviceListByDeviceClass), findsOneWidget);
  });

  testWidgets(
      "switching segment inside Devices clears the previous view's owned filter",
      (tester) async {
    await pumpShell(tester);
    final state = tester.state<DeviceTabsState>(find.byType(DeviceTabs));

    await tester.tap(find.text("Devices"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text("Locations"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    state.filter.locationIds = ["location-1"];
    expect(state.filter.locationIds, ["location-1"]);

    await tester.tap(find.text("Groups"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(state.filter.locationIds, isNull);
  });

  testWidgets("switching bar tabs clears the owned filter of the view left",
      (tester) async {
    await pumpShell(tester);
    final state = tester.state<DeviceTabsState>(find.byType(DeviceTabs));

    // Starts on Favorites, the only bar tab (not just segment) with an
    // owned filter.
    state.filter.favorites = true;
    expect(state.filter.favorites, true);

    await tester.tap(find.text("Sensors"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(state.filter.favorites, isNull);
  });

  test("legacy start-page values map to the Devices bar tab", () {
    expect(barTabForView(tabLocations), tabDevices);
    expect(barTabForView(tabGroups), tabDevices);
    expect(barTabForView(tabNetworks), tabDevices);
    expect(barTabForView(tabClasses), tabDevices);
    for (final tab in navBarTabs) {
      expect(barTabForView(tab), tab);
    }
  });

  testWidgets(
      "a stored legacy start page opens Devices on that segment",
      (tester) async {
    // A Hive write, like the Settings calls in golden_app_bar_test.dart -
    // never resolves inside testWidgets' fake-async zone without this.
    await tester.runAsync(() => Settings.setInitialTab(tabGroups));
    await pumpShell(tester);

    expect(find.byType(GroupList), findsOneWidget);
    // The main bar highlights Devices, not a tab of its own for Groups.
    expect(find.text("Groups"), findsOneWidget);
    expect(find.text("Devices"), findsOneWidget);
    final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navBar.selectedIndex, navBarTabs.indexOf(tabDevices));
  });

  testWidgets("a disabled bar tab cannot be selected", (tester) async {
    await tester.runAsync(() => Settings.setLocalMode(true));
    await pumpShell(tester);

    // Local mode with no cached smart services disables Dashboard/Services.
    expect(find.byTooltip("Currently unavailable"), findsWidgets);

    await tester.tap(find.text("Dashboard"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(Dashboard), findsNothing);
    expect(find.byType(DeviceListFavorites), findsOneWidget);
    expect(toastedUnavailable(), isTrue);
    // fluttertoast schedules its own timer for how long the toast shows;
    // let it fire before the tree is torn down, or the binding complains.
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets("a disabled segment cannot be selected", (tester) async {
    await tester.runAsync(() => Settings.setLocalMode(true));
    await pumpShell(tester);

    await tester.tap(find.text("Devices"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(DeviceList), findsOneWidget);

    // Local mode with no cached device classes disables the Classes segment.
    await tester.tap(find.text("Classes"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(DeviceListByDeviceClass), findsNothing);
    expect(find.byType(DeviceList), findsOneWidget);
    expect(toastedUnavailable(), isTrue);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets("the Devices segment bar spans the full width on a wide screen",
      (tester) async {
    await pumpShell(tester, size: const Size(800, 800));

    await tester.tap(find.text("Devices"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // A bar that shrinks to its tabs' content would center in the 800dp
    // width, leaving a gap on the left; spanning it keeps "All" near the edge.
    expect(tester.getTopLeft(find.text("All")).dx, lessThan(50));
  });

  testWidgets("the Classes segment is reachable by scrolling at 360dp width",
      (tester) async {
    await pumpShell(tester, size: const Size(360, 800));

    await tester.tap(find.text("Devices"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The five labels don't fit in 360dp - Classes' own edge lies past the
    // viewport, which is exactly what makes scrolling necessary for it.
    expect(tester.getRect(find.text("Classes")).right, greaterThan(360));

    await tester.drag(find.text("Locations"), const Offset(-400, 0));
    await tester.pump();
    await tester.tap(find.text("Classes"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(DeviceListByDeviceClass), findsOneWidget);
  });
}
