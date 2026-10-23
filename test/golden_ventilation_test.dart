/*
 * Copyright (c) 2026 InfAI (CC SES)
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

@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/base.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/shared/widget_info.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

// A file of its own: a second testWidgets in golden_dashboard_test.dart whose
// widget makes a request would not get its answer (docs/testing.md).
void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  // The ventilation card with four rooms: one helps, one helps less, one
  // does not help and one has no reading. Both themes in one test - see
  // golden_device_tabs_shell_test.dart for why.
  testWidgets("ventilation", (tester) async {
    for (final dark in [false, true]) {
      final suffix = dark ? "dark" : "light";

      final backend = FakeBackend();
      backend.serveJson("GET", "/widget-data/ventilation", 200, {
        "key": "dep-1_ventilation_state",
        "deployment_id": "dep-1",
        "updated_at": "2026-10-23T07:59:12.123Z",
        "value": {
          "outdoor": {"t": 8.1, "rh": 90.0, "valid": true},
          "rooms": [
            {"name": "Schlafzimmer", "state": "helps", "t": 21.3, "rh": 74.2, "rh_after": 55.1},
            {"name": "Bad", "state": "helps", "t": 22.0, "rh": 68.0, "rh_after": 61.0},
            {"name": "Wohnzimmer", "state": "no_benefit", "t": 21.0, "rh": 52.0, "rh_after": 49.0},
            {"name": "Keller", "state": "missing"},
          ],
          "threshold": 60,
        },
      });
      serveGoldenBackend(backend);

      final w = (await SmartServiceModuleWidget.fromWidgetInfo(
          "ventilation-$suffix",
          WidgetInfo.fromJson({
            "widget_type": smSeVentilationType,
            "widget_data": {
              "request": {"method": "GET", "url": "https://api.test/widget-data/ventilation", "body": null, "need_token": false},
              "labels": {
                "title": "Lüftungsempfehlung",
                "helps": "Lüften lohnt sich",
                "no_benefit": "Lüften lohnt nicht",
                "missing": "Messwert fehlt",
                "outside": "Außen",
                "updated": "Stand",
              },
            },
          })))!;
      await tester.runAsync(() => w.refresh());
      await pumpGolden(
        tester,
        Scaffold(
            body: Builder(
                builder: (c) => Card(
                    margin: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.sm),
                    // as the dashboard builds it: no padding of the card's own
                    child: w.build(c, false)))),
        dark: dark,
      );
      await expectLater(find.byType(MaterialApp), matchesGoldenFile("goldens/ventilation_$suffix.png"));

      if (!dark) {
        // The rows have fixed heights: twice the text size must not overflow
        // them, the widget limits the scale.
        await pumpGolden(
          tester,
          Builder(
              builder: (c) => MediaQuery(
                  data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(2.0)),
                  child: Scaffold(
                      body: Card(
                          margin: const EdgeInsets.symmetric(horizontal: Spacing.lg, vertical: Spacing.sm),
                          child: w.build(c, false))))),
          dark: dark,
        );
        expect(tester.takeException(), isNull);
      }

      resetAppStateForGolden();
      resetGoldenBackend();
    }
  });
}
