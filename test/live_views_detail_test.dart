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
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/detail_page.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';
import 'live_views_support.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  final made = <RecordingConnection>[];

  setUp(() {
    made.clear();
    recordConnectionsInto(made);
  });

  tearDown(() {
    restoreConnections();
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  // One testWidgets: the page requests its states on open, see docs/testing.md.
  testWidgets('a device page watches its device while open, a group page watches nothing', (tester) async {
    serveGoldenBackend(FakeBackend());
    final device = testDevice('dev-1');
    bindToPairedGateway(['dev-1-local']);

    // Opened from a host route, so a pop returns to it.
    await pumpGolden(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => DetailPage(device, null)),
            ),
            child: const Text('Open device'),
          ),
        ),
      ),
      dark: false,
    );
    expect(made, isEmpty, reason: 'nothing watched before a page shows a device');

    await tester.tap(find.text('Open device'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(DetailPage), findsOneWidget);
    expect(made, hasLength(1));
    expect(made.single.topics, {gatewayTopic(device)});

    Navigator.of(tester.element(find.byType(DetailPage))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(DetailPage), findsNothing);
    expect(made.single.topics, isEmpty, reason: 'the page released its device on pop');
    expect(made.single.disconnects, greaterThan(0));

    // A group page has no device to watch.
    final group = DeviceGroup('group-1', 'Group', const [], '', const [], null);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(home: DetailPage(null, group)),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(DetailPage), findsOneWidget);
    expect(made, hasLength(1), reason: 'a group page opens no connection');
    expect(made.single.topics, isEmpty);
  });
}
