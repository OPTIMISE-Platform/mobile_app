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
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/models/function.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/detail_page.dart';
import 'package:mobile_app/widgets/tabs/shared/state_time.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
    resetGoldenBackend();
    stateTimeClock = DateTime.now;
  });

  testWidgets('the detail page shows when each value and the device last sent',
      (tester) async {
    stateTimeClock = () => DateTime.utc(2026, 11, 6, 15, 59, 59);
    final backend = FakeBackend();
    backend.serveJson('POST', '/device-command/commands/batch', 200, [
      {'status_code': 200, 'message': 230, 'time': '2026-11-06T15:47:59Z'},
      {'status_code': 200, 'message': 4, 'time': '2026-11-06T15:20:59Z'},
    ]);
    serveGoldenBackend(backend);
    for (final f in ['a', 'b']) {
      AppState().platformFunctions['function-$f'] =
          PlatformFunction('function-$f', f, '', 'Reading $f');
    }
    final d = DeviceInstance('dev-1', 'dev-1-local', 'Meter', null, 'type-1',
        false, 'owner-1', 'Meter', DeviceConnectionStatus.online);
    for (final path in ['a', 'b']) {
      d.states.add(DeviceState(null, 'svc-1', 'group-1', 'function-$path', null,
          false, null, null, d.id, path, null)
        ..deviceInstance = d);
    }
    AppState().devices.add(d);

    await pumpGolden(tester, DetailPage(d, null), dark: false);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    expect(find.byKey(const Key('detailPageLastMessage')), findsOneWidget);
    expect(find.text('Last message 12 min ago'), findsOneWidget);
    expect(find.text('12 min ago'), findsOneWidget);
    expect(find.text('39 min ago'), findsOneWidget);

    // An open page keeps up with the clock: a minute later every relative
    // time has moved on without a reload.
    stateTimeClock = () => DateTime.utc(2026, 11, 6, 16, 4, 59);
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('Last message 17 min ago'), findsOneWidget);
    expect(find.text('17 min ago'), findsOneWidget);
    expect(find.text('44 min ago'), findsOneWidget);
    stateTimeClock = () => DateTime.utc(2026, 11, 6, 15, 59, 59);
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('Last message 12 min ago'), findsOneWidget);

    // A tap on the caption switches that row to the absolute time.
    await tester.tap(find.text('39 min ago'));
    await tester.pump();
    expect(find.text('39 min ago'), findsNothing);
    expect(find.text('15:20'), findsOneWidget);
    expect(find.text('12 min ago'), findsOneWidget);
    await tester.tap(find.text('15:20'));
    await tester.pump();
    expect(find.text('39 min ago'), findsOneWidget);

    // Without any time the header line goes and the rows show only values.
    for (final s in d.states) {
      s.lastMessageTime = null;
    }
    d.notifyStateChanged();
    await tester.pump();
    expect(find.byKey(const Key('detailPageLastMessage')), findsNothing);
    expect(find.textContaining('min ago'), findsNothing);
    expect(find.textContaining('230'), findsOneWidget);

    // At a large text scale the times, under the titles, must not overflow.
    final errors = <FlutterErrorDetails>[];
    final oldOnError = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = oldOnError);
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final s in d.states) {
      s.lastMessageTime = DateTime.utc(2026, 11, 6, 15, 20, 59);
    }
    d.notifyStateChanged();
    await tester.pump();
    FlutterError.onError = oldOnError;
    expect(find.text('39 min ago'), findsNWidgets(2));
    expect(errors.map((e) => e.exceptionAsString()), isEmpty);
  });
}
