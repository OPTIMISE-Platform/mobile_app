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
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_class.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/models/function.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/detail_page.dart';

import 'golden_helper.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
  });

  // DetailPage is a pushed route with its own Scaffold and no
  // bottomNavigationBar, so it does not get the system nav bar's inset
  // removed the way the main tabs do (see Spacing.listPadding's doc comment).
  testWidgets(
      'the last row scrolls fully above the system navigation bar inset',
      (tester) async {
    tester.view.padding = const FakeViewPadding(bottom: 48);
    tester.view.viewPadding = const FakeViewPadding(bottom: 48);
    addTearDown(() {
      tester.view.resetPadding();
      tester.view.resetViewPadding();
    });

    final lamp = DeviceClass("class-1", "Lamps", "");
    AppState().deviceClasses[lamp.id] = lamp;
    AppState().deviceTypes["device-type-1"] =
        DeviceType("device-type-1", "Smart Lamp", "", lamp.id, [], null);
    final d = DeviceInstance("device-1", "device-1-local", "Living room lamp",
        null, "device-type-1", false, "owner-1", "Living room lamp",
        DeviceConnectionStatus.offline);
    // Enough rows, each with its own function so none collapse into another,
    // to overflow the small surface below and require scrolling to the end.
    for (var i = 0; i < 20; i++) {
      final id = "function-${i.toString().padLeft(2, '0')}";
      AppState().platformFunctions[id] =
          PlatformFunction(id, "function_$i", "", "Function $i");
      d.states.add(DeviceState(i.toDouble(), "service-$i", "service-group-$i",
          id, "aspect-$i", false, null, null, d.id, "path", "group"));
    }
    AppState().devices.add(d);

    await pumpGolden(tester, DetailPage(d, null),
        dark: false, size: const Size(412, 600));

    await tester.drag(find.byType(ListView), const Offset(0, -10000));
    await tester.pump();

    final lastRowBottom = tester.getBottomLeft(find.text("Function 19")).dy;
    expect(lastRowBottom, lessThanOrEqualTo(600 - 48),
        reason: "the last row must be scrollable clear of the system nav "
            "bar's inset, not left sitting behind it");
  });
}
