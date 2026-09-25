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
import 'package:mobile_app/models/smart_service.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/keyed_list.dart';
import 'package:mobile_app/widgets/tabs/dashboard/dashboard.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  Map<String, dynamic> module(String id, String instanceId, String text) => {
        "design_id": "design-1",
        "id": id,
        "instance_id": instanceId,
        "release_id": "release-1",
        "user_id": "user-1",
        "module_type": "widget",
        "module_data": {
          "widget_type": "text",
          "widget_data": {"text": text}
        },
      };

  /// Drags the handle at [index] by [offset] and returns the order
  /// `Settings` persisted afterwards.
  Future<List<Pair<String, String>>> dragAndPersist(
      WidgetTester tester, int index, Offset offset) async {
    // A large overshoot rather than a measured tile height: it lands the drag
    // at the first or last slot regardless of the card's rendered size.
    await tester.drag(find.byIcon(Icons.reorder).at(index), offset);
    // Not pumpAndSettle: the app bar's update icon and other widgets here
    // animate forever, see pumpGolden's own doc comment.
    await tester.pump(const Duration(milliseconds: 500));
    return Settings.getSmartServiceDashboards().single.widgetAndInstanceIds;
  }

  // One mount for both drags, dragging down and then back up, rather than
  // remounting for a second scenario: a second Dashboard fetch inside the
  // same test hangs (a stray timer or memoized future from the first one
  // outliving its FakeBackend - see golden_dashboard_test.dart's note on
  // why a screen's variants share one testWidgets).
  testWidgets('dragging persists the new order', (tester) async {
    final backend = FakeBackend();
    backend.serveJson("GET", "/smart-services/repository/modules", 200, [
      module("module-1", "instance-1", "First"),
      module("module-2", "instance-2", "Second"),
      module("module-3", "instance-3", "Third"),
    ]);
    serveGoldenBackend(backend);

    final dashboard = SmartServiceDashboard("dashboard-1", "Home", [
      Pair("module-1", "instance-1"),
      Pair("module-2", "instance-2"),
      Pair("module-3", "instance-3"),
    ]);
    await tester.runAsync(() => Settings.setSmartServiceDashboards([dashboard]));

    await pumpGolden(tester, const Dashboard(), dark: false);

    final down = await dragAndPersist(tester, 0, const Offset(0, 1000));
    expect(down.map((p) => p.k), ["module-2", "module-3", "module-1"],
        reason: "dragging the first widget down should move it to the end");

    final up = await dragAndPersist(tester, 2, const Offset(0, -1000));
    expect(up.map((p) => p.k), ["module-1", "module-2", "module-3"],
        reason: "dragging the now-last widget up should move it to the start");
  });
}
