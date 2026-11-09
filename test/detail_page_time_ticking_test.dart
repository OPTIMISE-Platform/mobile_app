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

  testWidgets('the times count up in seconds and a new message restarts one',
      (tester) async {
    var clock = DateTime.utc(2026, 11, 6, 15, 59, 59);
    stateTimeClock = () => clock;
    Future<void> tick() async {
      clock = clock.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }

    final backend = FakeBackend();
    backend.serveJson('POST', '/device-command/commands/batch', 200, [
      {'status_code': 200, 'message': 230, 'time': '2026-11-06T15:59:56Z'},
      {'status_code': 200, 'message': 4, 'time': '2026-11-06T15:40:59Z'},
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

    expect(find.text('Last message 3 seconds ago'), findsOneWidget);
    expect(find.text('3 seconds ago'), findsOneWidget);
    expect(find.text('19 min ago'), findsOneWidget);

    for (var s = 4; s < 60; s++) {
      await tick();
      expect(find.text('Last message $s seconds ago'), findsOneWidget);
      expect(find.text('$s seconds ago'), findsOneWidget);
    }
    await tick();
    expect(find.text('Last message 1 min ago'), findsOneWidget);
    expect(find.text('1 min ago'), findsOneWidget);
    // The other value counts its own minutes: 15:40:59 turns 20 minutes old
    // at 16:00:59, three seconds later.
    expect(find.text('19 min ago'), findsOneWidget);
    await tick();
    await tick();
    expect(find.text('19 min ago'), findsOneWidget);
    await tick();
    expect(find.text('20 min ago'), findsOneWidget);
    expect(find.text('Last message 1 min ago'), findsOneWidget);

    // A new message for one value restarts its time and the header's, the
    // other value keeps its own.
    d.states[1].value = 5;
    d.states[1].lastMessageTime = clock;
    d.notifyStateChanged();
    await tester.pump();
    expect(find.text('Last message just now'), findsOneWidget);
    expect(find.text('just now'), findsOneWidget);
    expect(find.text('1 min ago'), findsOneWidget);
    await tick();
    expect(find.text('Last message 1 second ago'), findsOneWidget);
    expect(find.text('1 second ago'), findsOneWidget);
    expect(find.text('1 min ago'), findsOneWidget);
    await tick();
    expect(find.text('2 seconds ago'), findsOneWidget);
  });
}
