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


import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/widgets/tabs/shared/state_time.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';
import 'sensor_switch_fixture.dart';

/// Answers each read of the command batch with a value, and with a time only
/// for the ids in [timed], as device-command does for a stored value. A group
/// is given one too, which its card must not show.
class _TimedBackend extends FakeBackend {
  final Set<String> timed;

  _TimedBackend(this.timed);

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (options.uri.path != batchPath) {
      return super.fetch(options, requestStream, cancelFuture);
    }
    requests.add(options);
    final batch = (jsonDecode(options.data as String) as List)
        .cast<Map<String, dynamic>>();
    final answers = [
      for (final c in batch)
        {
          'status_code': 200,
          'message': [true],
          if (timed.contains(c['device_id'] ?? c['group_id']))
            'time': '2026-11-06T15:47:59Z',
        }
    ];
    return ResponseBody.fromString(jsonEncode(answers), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }
}

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
    resetGoldenBackend();
    stateTimeClock = DateTime.now;
  });

  // One testWidgets for every case, see sensor_switch_tile_device_test.dart.
  testWidgets('sensor cards show when a device last sent, group cards do not',
      (tester) async {
    stateTimeClock = () => DateTime.utc(2026, 11, 6, 15, 59, 59);
    final backend = _TimedBackend({'fan', 'hall'});
    backend.serveJson('GET', devicesPath, 200, [
      deviceJson('fan', 'Bathroom fan', deviceTypeId: 'plug'),
      deviceJson('lamp', 'Desk lamp', deviceTypeId: 'plug'),
    ]);
    backend.serveJson('POST', '/db/v3/queries', 200, [[]]);
    // The lamp's answer has no time, so the page asks the platform for it.
    backend.serveJson('POST', '/db/v3/last-values', 200, [
      {'time': '2026-11-06T13:59:59Z', 'value': true}
    ]);
    serveGoldenBackend(backend);
    await warmUpMgwStorage(tester);
    registerOnOffFunctions();
    AppState().deviceTypes['plug'] = plugType('plug');
    // The platform is asked only for event services; a request service was
    // just answered by the device itself.
    AppState()
        .deviceTypes['plug']!
        .services
        .firstWhere((s) => s.id == 'svc-get')
        .interaction = 'event';
    AppState().deviceGroups.add(plugGroup('hall', ['class-plug']));

    await mountSensorPage(tester, [
      plugPin('fan', 'Fan'),
      plugPin('lamp', 'Lamp'),
      groupPin('hall', 'Hall'),
    ]);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    expect(inCard('Fan', findShownText('12 min ago')), findsOneWidget);
    expect(inCard('Lamp', findShownText('2 h ago')), findsOneWidget);
    expect(inCard('Hall', find.textContaining('ago')), findsNothing);
    // Even a group state that carries a time shows none on its card.
    final group = AppState().deviceGroups.single;
    group.states.first.lastMessageTime = DateTime.utc(2026, 11, 6, 15, 50);
    group.notifyStateChanged();
    await tester.pump();
    expect(inCard('Hall', find.textContaining('ago')), findsNothing);
    final lastValues = backend.requests
        .where((r) => r.uri.path == '/db/v3/last-values')
        .toList();
    expect(lastValues, hasLength(1));
    expect(jsonDecode(lastValues.single.data as String), [
      {'deviceId': 'lamp', 'serviceId': 'svc-get', 'columnName': 'on'}
    ]);

    // A fresh page at a large text scale: the caption must not overflow.
    final errors = <FlutterErrorDetails>[];
    final oldOnError = FlutterError.onError;
    FlutterError.onError = errors.add;
    await mountSensorPage(tester, [plugPin('fan', 'Fan')],
        size: const Size(320, 800), textScale: 2.0);
    await tester.pump();
    FlutterError.onError = oldOnError;
    expect(errors.map((e) => e.exceptionAsString()), isEmpty);
    expect(inCard('Fan', findShownText('12 min ago')), findsOneWidget);
  });
}
