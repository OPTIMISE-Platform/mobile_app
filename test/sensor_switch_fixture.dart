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

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/content.dart';
import 'package:mobile_app/models/content_variable.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/models/function.dart';
import 'package:mobile_app/models/sensor_pin.dart';
import 'package:mobile_app/models/sensor_tab.dart';
import 'package:mobile_app/models/service.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/widgets/tabs/sensors/sensor_values.dart';
import 'package:mobile_app/widgets/tabs/sensors/switch_tile.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

/// Shared by the switch tile tests: a plug device type, groups of plugs, and a
/// backend that behaves like the plugs it switches.

const batchPath = '/device-command/commands/batch';
const devicesPath = '/device-repository/extended-devices';

String get onOffFunction => dotenv.env['FUNCTION_GET_ON_OFF_STATE']!;
String get setOnFunction => dotenv.env['FUNCTION_SET_ON_STATE']!;
String get setOffFunction => dotenv.env['FUNCTION_SET_OFF_STATE']!;

ContentVariable _variable(String name, String functionId, String type) =>
    ContentVariable(
      'cv-$name',
      name,
      null,
      null,
      'power',
      functionId,
      type,
      null,
      null,
      null,
      const ['power'],
    );

/// A plug: its on/off reading and both controls, in one service group as
/// device types model a switchable device.
DeviceType plugType(String id) => DeviceType(id, 'Plug', '', 'class-plug', [
  Service('svc-get', 'local-get', 'Get', '', 'protocol-1', 'request',
      'group-1', null, [
    Content('c-get', 'json', 'segment-1',
        _variable('on', onOffFunction, 'https://schema.org/Boolean')),
  ]),
  Service('svc-on', 'local-on', 'On', '', 'protocol-1', 'request', 'group-1', [
    Content('c-on', 'json', 'segment-1',
        _variable('on', setOnFunction, 'https://schema.org/Boolean')),
  ], null),
  Service('svc-off', 'local-off', 'Off', '', 'protocol-1', 'request',
      'group-1', [
    Content('c-off', 'json', 'segment-1',
        _variable('off', setOffFunction, 'https://schema.org/Boolean')),
  ], null),
], null);

/// A meter that reports whether it is on but has no control to switch it.
DeviceType readerType(String id) => DeviceType(id, 'Meter', '', 'class-meter', [
  Service('svc-get', 'local-get', 'Get', '', 'protocol-1', 'request',
      'group-1', null, [
    Content('c-get', 'json', 'segment-1',
        _variable('on', onOffFunction, 'https://schema.org/Boolean')),
  ]),
], null);

/// Names the on/off functions, which a group's states need and the cards use
/// as their title.
void registerOnOffFunctions() {
  final functions = AppState().platformFunctions;
  functions[onOffFunction] =
      PlatformFunction(onOffFunction, 'on_off', 'concept-on-off', 'Power');
  functions[setOnFunction] =
      PlatformFunction(setOnFunction, 'set_on', '', 'Switch on');
  functions[setOffFunction] =
      PlatformFunction(setOffFunction, 'set_off', '', 'Switch off');
}

SensorPin plugPin(String deviceId, String alias) => SensorPin(
  deviceId: deviceId,
  functionId: onOffFunction,
  aspectId: 'power',
  aspectIds: const ['power'],
  serviceGroupKey: 'group-1',
  alias: alias,
);

SensorPin groupPin(String groupId, String alias,
        {String deviceClassId = 'class-plug'}) =>
    SensorPin(
      groupId: groupId,
      deviceClassId: deviceClassId,
      functionId: onOffFunction,
      aspectId: 'power',
      aspectIds: const ['power'],
      alias: alias,
    );

/// A group of plugs of [deviceClassIds], each class bringing its own
/// reading and controls.
DeviceGroup plugGroup(String id, List<String> deviceClassIds) {
  DeviceGroupCriteria criterion(String classId, String functionId) =>
      DeviceGroupCriteria.fromJson({
        'aspect_id': 'power',
        'aspect_ids': ['power'],
        'device_class_id': classId,
        'function_id': functionId,
        'interaction': 'request',
      });
  return DeviceGroup(id, 'Group $id', [
    for (final classId in deviceClassIds) ...[
      criterion(classId, onOffFunction),
      criterion(classId, setOnFunction),
      criterion(classId, setOffFunction),
    ],
  ], '', [], null);
}

/// Answers the command batch like the plugs would: a read returns [values]
/// for the device or group (a group's as the list of its members), a control
/// sets them. A device or group without an entry answers 502, so its state is
/// unknown.
class PlugBackend extends FakeBackend {
  final Map<String, dynamic> values = {};

  /// Devices and groups whose controls answer 500 "boom".
  final Set<String> refusing = {};

  /// Every command sent, in order.
  final List<Map<String, dynamic>> commands = [];

  /// While set, a batch holding a control waits for it.
  Completer<void>? holdControls;

  /// While set, a value load (reads preferring the last event, unlike a
  /// read-back) waits for it, answering with the values from when it was
  /// sent.
  Completer<void>? holdLoads;

  List<Map<String, dynamic>> get controls =>
      commands.where((c) => c['function_id'] != onOffFunction).toList();

  List<Map<String, dynamic>> commandsFor(String id) => commands
      .where((c) => c['device_id'] == id || c['group_id'] == id)
      .toList();

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    if (options.uri.path != batchPath) {
      return super.fetch(options, requestStream, cancelFuture);
    }
    requests.add(options);
    final batch = (jsonDecode(options.data as String) as List)
        .cast<Map<String, dynamic>>();
    commands.addAll(batch);
    final isLoad = options.uri.queryParameters['prefer_event_value'] == 'true' &&
        batch.every((c) => c['function_id'] == onOffFunction);
    if (isLoad) {
      final answers = [for (final command in batch) _answer(command)];
      final hold = holdLoads;
      if (hold != null) await hold.future;
      return _batchAnswer(answers);
    }
    final hold = holdControls;
    if (hold != null && batch.any((c) => c['function_id'] != onOffFunction)) {
      await hold.future;
    }
    return _batchAnswer([for (final command in batch) _answer(command)]);
  }

  ResponseBody _batchAnswer(List<Map<String, dynamic>> answers) {
    return ResponseBody.fromString(jsonEncode(answers), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  Map<String, dynamic> _answer(Map<String, dynamic> command) {
    final id = (command['device_id'] ?? command['group_id']) as String;
    final function = command['function_id'];
    if (function == onOffFunction) {
      if (!values.containsKey(id)) {
        return {'status_code': 502, 'message': 'upstream reply null'};
      }
      final value = values[id];
      return {'status_code': 200, 'message': value is List ? value : [value]};
    }
    if (refusing.contains(id)) return {'status_code': 500, 'message': 'boom'};
    final on = function == setOnFunction;
    final current = values[id];
    // An unreachable member (null) stays unreachable.
    values[id] = current is List
        ? [for (final member in current) member == null ? null : on]
        : on;
    return {'status_code': 200, 'message': null};
  }
}

/// Captures what the widgets toast.
List<String> captureToasts() {
  final toasts = <String>[];
  const channel = MethodChannel('PonnamKarthik/fluttertoast');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'showToast') {
      toasts.add((call.arguments as Map)['msg'] as String);
    }
    return true;
  });
  addTearDown(() =>
      messenger.setMockMethodCallHandler(channel, (call) async => true));
  return toasts;
}

/// Mounts the sensors page on [pins] and lets it load. A second call mounts
/// a fresh page, as leaving the tab and coming back does.
Future<void> mountSensorPage(WidgetTester tester, List<SensorPin> pins,
    {bool dark = false,
    Size size = goldenSurfaceSize,
    double textScale = 1.0,
    bool settleLoad = true}) async {
  await tester.runAsync(() => Settings.setSensorTabs(
      [SensorTab(id: 'tab-1', name: 'Switches', pins: pins)]));
  await pumpGolden(
    tester,
    Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: const Scaffold(body: SensorValues()),
      ),
    ),
    dark: dark,
    size: size,
  );
  if (settleLoad) await settle(tester);
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The card titled [alias].
Finder cardOf(String alias) =>
    find.ancestor(of: find.text(alias), matching: find.byType(Card));

Finder inCard(String alias, Finder finder) =>
    find.descendant(of: cardOf(alias), matching: finder);

Switch switchOf(WidgetTester tester, String alias) =>
    tester.widget<Switch>(inCard(alias, find.byType(Switch)));

String labelOf(WidgetTester tester, String alias) => tester
    .widget<Text>(find.descendant(
        of: inCard(alias, find.byType(SwitchTileFooter)),
        matching: find.byType(Text)))
    .data!;

InkWell inkWellOf(WidgetTester tester, String alias) =>
    tester.widget<InkWell>(inCard(alias, find.byType(InkWell)).first);
