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


import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_command_response.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/models/service.dart';
import 'package:mobile_app/services/api_available.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

const _batch = '/device-command/commands/batch';
const _lastValues = '/db/v3/last-values';

void main() {
  late FakeBackend backend;

  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  setUp(() {
    backend = FakeBackend();
    serveGoldenBackend(backend);
  });

  tearDown(() {
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  /// A device with one reading per entry of [paths] and one control.
  DeviceInstance device(List<String> paths) {
    final d = DeviceInstance('dev-1', 'dev-1-local', 'Meter', null, 'type-1',
        false, 'owner-1', 'Meter', DeviceConnectionStatus.online);
    for (final path in paths) {
      d.states.add(DeviceState(1, 'svc-1', 'group-1', 'function-$path', null,
          false, null, null, d.id, path, null)
        ..deviceInstance = d);
    }
    d.states.add(DeviceState(null, 'svc-2', 'group-1', 'function-set', null,
        true, null, null, d.id, 'set', null)
      ..deviceInstance = d);
    return d;
  }

  List<dynamic> sentBody(String path) {
    final sent = backend.requests.where((r) => r.uri.path == path).toList();
    expect(sent, hasLength(1), reason: 'requests to $path');
    return jsonDecode(sent.single.data as String) as List;
  }

  Future<void> until(bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test('DeviceCommandResponse reads the time of a stored value', () {
    final stored = DeviceCommandResponse.fromJson(
        {'status_code': 200, 'message': 1, 'time': '2026-11-06T15:47:59.183Z'});
    expect(stored.lastMessageTime, DateTime.utc(2026, 11, 6, 15, 47, 59, 183));

    final live = DeviceCommandResponse.fromJson({'status_code': 200, 'message': 1});
    expect(live.time, isNull);
    expect(live.lastMessageTime, isNull);

    final broken = DeviceCommandResponse.fromJson(
        {'status_code': 200, 'message': 1, 'time': 'yesterday'});
    expect(broken.lastMessageTime, isNull);
  });

  test('a state takes its time from the batch answer, the rest from last-values',
      () async {
    final d = device(['a', 'b']);
    backend.serveJson('POST', _batch, 200, [
      {'status_code': 200, 'message': 1, 'time': '2026-11-06T15:47:59Z'},
      {'status_code': 200, 'message': 2},
    ]);
    backend.serveJson('POST', _lastValues, 200, [
      {'time': '2026-11-06T15:30:00.5Z', 'value': 2}
    ]);

    await AppState().loadStates([d], []);
    await until(() => d.states[1].lastMessageTime != null);

    expect(d.states[0].lastMessageTime, DateTime.utc(2026, 11, 6, 15, 47, 59));
    expect(d.states[0].value, 1);
    expect(d.states[1].lastMessageTime,
        DateTime.utc(2026, 11, 6, 15, 30, 0, 500));
    expect(d.states[1].value, 2);
    expect(d.states[2].lastMessageTime, isNull, reason: 'a control has none');
    expect(sentBody(_lastValues), [
      {'deviceId': 'dev-1', 'serviceId': 'svc-1', 'columnName': 'b'}
    ]);
  });

  test('no last-values request when every state has its time', () async {
    final d = device(['a']);
    backend.serveJson('POST', _batch, 200, [
      {'status_code': 200, 'message': 1, 'time': '2026-11-06T15:47:59Z'},
    ]);

    await AppState().loadStates([d], []);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(backend.requests.where((r) => r.uri.path == _lastValues), isEmpty);
  });

  test('one request asks for exactly the states without a time', () async {
    final d = device(['a', 'b', 'c']);
    d.states[1].lastMessageTime = DateTime.utc(2026, 11, 6, 12);
    backend.serveJson('POST', _lastValues, 200, [
      {'time': '2026-11-06T10:00:00Z', 'value': 1},
      {'time': '2026-11-06T11:00:00Z', 'value': 3},
    ]);

    await AppState().loadMissingStateTimes([d]);

    expect(sentBody(_lastValues), [
      {'deviceId': 'dev-1', 'serviceId': 'svc-1', 'columnName': 'a'},
      {'deviceId': 'dev-1', 'serviceId': 'svc-1', 'columnName': 'c'},
    ]);
    expect(d.states[0].lastMessageTime, DateTime.utc(2026, 11, 6, 10));
    expect(d.states[1].lastMessageTime, DateTime.utc(2026, 11, 6, 12),
        reason: 'a time that is there is kept');
    expect(d.states[2].lastMessageTime, DateTime.utc(2026, 11, 6, 11));
  });

  test('a refused request is asked column by column; a refused column is left out next time',
      () async {
    final columnsBackend = _ColumnsBackend(refused: {'bad'});
    serveGoldenBackend(columnsBackend);
    final d = device(['a', 'bad', 'c']);
    d.states[0].value = 5;

    await AppState().loadMissingStateTimes([d]);

    expect(columnsBackend.bodies.first, ['a', 'bad', 'c']);
    // The single requests run concurrently, so their order is not fixed.
    expect(columnsBackend.bodies.skip(1).map((b) => b.join(',')),
        unorderedEquals(['a', 'bad', 'c']));
    expect(d.states[0].lastMessageTime, DateTime.utc(2026, 11, 6, 10));
    expect(d.states[1].lastMessageTime, isNull);
    expect(d.states[2].lastMessageTime, DateTime.utc(2026, 11, 6, 10));
    expect(d.states[0].value, 5, reason: 'a time never changes a value');

    d.states[0].lastMessageTime = null;
    d.states[2].lastMessageTime = null;
    columnsBackend.bodies.clear();
    await AppState().loadMissingStateTimes([d]);

    expect(columnsBackend.bodies, [
      ['a', 'c']
    ]);
  });

  test('a device the platform no longer grants (404) is split off like a refused column',
      () async {
    final columnsBackend = _ColumnsBackend(refused: {'gone'}, refusedStatus: 404);
    serveGoldenBackend(columnsBackend);
    final d = device(['a', 'gone']);

    await AppState().loadMissingStateTimes([d]);

    expect(columnsBackend.bodies, hasLength(3));
    expect(d.states[0].lastMessageTime, DateTime.utc(2026, 11, 6, 10));
    expect(d.states[1].lastMessageTime, isNull);
  });

  test('writing a value drops its time', () {
    final d = device(['a']);
    d.states[0].lastMessageTime = DateTime.utc(2026, 11, 6, 10);
    d.states[0].value = 2;
    expect(d.states[0].lastMessageTime, isNull);
  });

  test('a reading without a value or of a request service is not asked for', () async {
    final d = device(['a', 'b', 'c']);
    d.states[1].value = null;
    d.states[2].serviceId = 'svc-request';
    AppState().deviceTypes['type-1'] = DeviceType('type-1', 'Meter', '', 'class', [
      Service('svc-1', 'l1', 'Event', '', 'p', 'event', 'group-1', [], []),
      Service('svc-request', 'l2', 'Request', '', 'p', 'request', 'group-1', [], []),
    ], null);
    backend.serveJson('POST', _lastValues, 200, [
      {'time': '2026-11-06T10:00:00Z', 'value': 1}
    ]);

    await AppState().loadMissingStateTimes([d]);

    expect(sentBody(_lastValues), [
      {'deviceId': 'dev-1', 'serviceId': 'svc-1', 'columnName': 'a'}
    ]);
  });

  test('a time arriving after its value was replaced is dropped, and a load '
      'meanwhile does not ask again', () async {
    final d = device(['a']);
    final gate = Completer<void>();
    backend.holds['POST $_lastValues'] = gate;
    backend.serveJson('POST', _lastValues, 200, [
      {'time': '2026-11-06T10:00:00Z', 'value': 1}
    ]);

    final first = AppState().loadMissingStateTimes([d]);
    await until(() => backend.requests.any((r) => r.uri.path == _lastValues));
    await AppState().loadMissingStateTimes([d]);
    d.states[0].value = 7;
    gate.complete();
    await first;

    expect(backend.requests.where((r) => r.uri.path == _lastValues), hasLength(1));
    expect(d.states[0].lastMessageTime, isNull);
    expect(d.states[0].value, 7);
  });

  test('a live answer of a request service takes the time of the answer', () async {
    final d = device(['a', 'b']);
    d.states[1].serviceId = 'svc-request';
    AppState().deviceTypes['type-1'] = DeviceType('type-1', 'Meter', '', 'class', [
      Service('svc-1', 'l1', 'Event', '', 'p', 'event', 'group-1', [], []),
      Service('svc-request', 'l2', 'Request', '', 'p', 'request', 'group-1', [], []),
    ], null);
    backend.serveJson('POST', _batch, 200, [
      {'status_code': 200, 'message': 1},
      {'status_code': 200, 'message': 2},
    ]);
    backend.serveJson('POST', _lastValues, 200, [
      {'time': '2026-11-06T10:00:00Z', 'value': 1}
    ]);

    final before = DateTime.now().toUtc();
    await AppState().loadStates([d], []);
    await until(() => d.states[0].lastMessageTime != null);

    expect(d.states[1].lastMessageTime, isNotNull);
    expect(d.states[1].lastMessageTime!.isBefore(before), isFalse);
    expect(d.states[0].lastMessageTime, DateTime.utc(2026, 11, 6, 10),
        reason: 'an event service still takes the stored time');
    expect(sentBody(_lastValues), [
      {'deviceId': 'dev-1', 'serviceId': 'svc-1', 'columnName': 'a'}
    ]);
  });

  test('a failure other than a refused column is not retried', () async {
    final d = device(['x', 'y']);
    backend.serveJson('POST', _lastValues, 500, {'error': 'down'});

    await AppState().loadMissingStateTimes([d]);

    expect(d.states[0].lastMessageTime, isNull);
    expect(d.states[1].lastMessageTime, isNull);
    expect(backend.requests.where((r) => r.uri.path == _lastValues), hasLength(1));
  });

  test('an answer of the wrong length is dropped', () async {
    final d = device(['a', 'b']);
    backend.serveJson('POST', _lastValues, 200, [
      {'time': '2026-11-06T10:00:00Z', 'value': 1}
    ]);

    await AppState().loadMissingStateTimes([d]);

    expect(d.states[0].lastMessageTime, isNull);
    expect(d.states[1].lastMessageTime, isNull);
  });

  test('no last-values request while the platform is unreachable', () async {
    final d = device(['a']);
    ApiAvailableService.setUnreachableForTest(true);

    await AppState().loadMissingStateTimes([d]);

    expect(backend.requests, isEmpty);
    expect(d.states[0].lastMessageTime, isNull);
  });
}

/// Answers last-values per column the way the platform does: 400 for the whole
/// request if any column in it is unknown, else a time per column.
class _ColumnsBackend extends FakeBackend {
  final Set<String> refused;
  final int refusedStatus;
  final List<List<String>> bodies = [];

  _ColumnsBackend({required this.refused, this.refusedStatus = 400});

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (options.uri.path != _lastValues) {
      return super.fetch(options, requestStream, cancelFuture);
    }
    requests.add(options);
    final columns = [
      for (final c in jsonDecode(options.data as String) as List)
        (c as Map)['columnName'] as String
    ];
    bodies.add(columns);
    if (columns.any(refused.contains)) {
      return ResponseBody.fromString('refused', refusedStatus);
    }
    return ResponseBody.fromString(
        jsonEncode([
          for (final _ in columns) {'time': '2026-11-06T10:00:00Z', 'value': 1}
        ]),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });
  }
}
