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
import 'package:mobile_app/models/notification.dart' as app;
import 'package:mobile_app/widgets/notifications/notification_list.dart';
import 'package:mobile_app/widgets/shared/grouped_list_tile.dart';
import 'package:mobile_app/widgets/shared/slice_position.dart';

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

  testWidgets(
      "dismissing the last of three notifications rounds the new last row "
      "immediately", (tester) async {
    final backend = FakeBackend();
    backend.serveJson("DELETE", "/notifications-v2/notifications", 200, null);
    serveGoldenBackend(backend);

    AppState().notifications.addAll([
      app.Notification("2026-01-01T10:00:00.000Z", "m1", "user-1", "n1", true, "First"),
      app.Notification("2026-01-02T10:00:00.000Z", "m2", "user-1", "n2", true, "Second"),
      app.Notification("2026-01-03T10:00:00.000Z", "m3", "user-1", "n3", true, "Third"),
    ]);

    await pumpGolden(tester, const NotificationList(), dark: false);

    expect(find.text("First"), findsOneWidget);
    expect(find.text("Second"), findsOneWidget);
    expect(find.text("Third"), findsOneWidget);

    await tester.drag(
        find.ancestor(of: find.text("Third"), matching: find.byType(Dismissible)),
        const Offset(-500, 0));
    // Drives the swipe through confirmDismiss, the resize-to-zero animation
    // and onDismissed. If the row is not dropped from the list in the same
    // frame onDismissed fires, Dismissible's own next build - still mounted,
    // its resize animation already complete - throws "A dismissed
    // Dismissible widget is still part of the tree".
    await tester.pumpAndSettle();

    expect(find.text("Third"), findsNothing);
    expect(find.text("First"), findsOneWidget);
    expect(find.text("Second"), findsOneWidget);

    final secondTile = tester.widget<GroupedListTile>(find.ancestor(
        of: find.text("Second"), matching: find.byType(GroupedListTile)));
    expect(secondTile.position, SlicePosition.last,
        reason:
            "Second is now the last row and should round its bottom corners "
            "as soon as Third is dismissed, not wait for a delete-many push");
  });
}
