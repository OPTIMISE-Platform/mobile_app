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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/models/function.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/shared/slice_position.dart';
import 'package:mobile_app/widgets/tabs/shared/device_list_item.dart';
import 'package:mobile_app/widgets/tabs/shared/device_state_action.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

const _batch = "/device-command/commands/batch";

void main() {
  late List<String> toasts;

  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  setUp(() {
    toasts = [];
    const channel = MethodChannel('PonnamKarthik/fluttertoast');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == "showToast") toasts.add((call.arguments as Map)["msg"] as String);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, (call) async => true));
  });

  tearDown(() {
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  late final onOff = dotenv.env['FUNCTION_GET_ON_OFF_STATE']!;
  late final setOff = dotenv.env['FUNCTION_SET_OFF_STATE']!;
  late final setOn = dotenv.env['FUNCTION_SET_ON_STATE']!;

  DeviceState state(DeviceInstance d, String functionId, bool controlling, {dynamic value}) {
    final s = DeviceState(value, "service-1", "group-1", functionId, null, controlling, null, null, d.id, "path", "group",
        aspectIds: const ["lamp"]);
    s.deviceInstance = d;
    return s;
  }

  /// A lamp that is on, with its on/off reading and, unless [withControls] is
  /// false, both controls in the same service group.
  (DeviceInstance, DeviceState) lamp({bool withControls = true}) {
    final d = DeviceInstance("device-1", "device-1-local", "Living room lamp", null, "device-type-1", false, "owner-1",
        "Living room lamp", DeviceConnectionStatus.online);
    final reading = state(d, onOff, false, value: true);
    d.states.add(reading);
    if (withControls) {
      d.states
        ..add(state(d, setOff, true))
        ..add(state(d, setOn, true));
    }
    return (d, reading);
  }

  List<String> sentFunctionIds(FakeBackend backend) => [
        for (final r in backend.requests.where((r) => r.uri.path == _batch))
          for (final command in jsonDecode(r.data as String) as List) command["function_id"] as String,
      ];

  /// Mounts the row and returns its toggle's callback. The toggle is called
  /// directly inside runAsync rather than tapped: a tap would start the real
  /// HTTP round trip inside the fake-async zone, where it never completes
  /// (docs/testing.md).
  Future<Future<void> Function()> mountToggle(WidgetTester tester, DeviceInstance d) async {
    await pumpGolden(tester, Scaffold(body: DeviceListItem(d, null, position: SlicePosition.only)), dark: false);
    final button = tester.widget<IconButton>(find.byType(IconButton));
    final dynamic onPressed = button.onPressed;
    return () async {
      final dynamic result = onPressed();
      if (result is Future) await result;
    };
  }

  testWidgets("toggling a row switches through the control and shows the value read back", (tester) async {
    final backend = FakeBackend();
    backend.serveJson("POST", _batch, 200, [
      {"status_code": 200, "message": [false]}
    ]);
    serveGoldenBackend(backend);
    final (d, reading) = lamp();
    final toggle = await mountToggle(tester, d);

    await tester.runAsync(() async {
      // Created here, not in the test body: completed from the fake zone's
      // future, the held request would resume only on a pump.
      final hold = Completer<void>();
      backend.holds["POST $_batch"] = hold;
      final running = toggle();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(reading.transitioning, isTrue, reason: "the row shows a spinner while the command runs");
      hold.complete();
      await running;
    });
    await tester.pump();

    expect(sentFunctionIds(backend), [setOff, onOff], reason: "switch off, then read the reading back");
    expect(reading.value, isFalse);
    expect(reading.transitioning, isFalse);
    expect(find.byType(DelayedCircularProgressIndicator), findsNothing);
    expect(toasts, isEmpty);
  });

  testWidgets("a refused command clears the spinner and keeps the old value", (tester) async {
    final backend = FakeBackend();
    backend.serveJson("POST", _batch, 200, [
      {"status_code": 500, "message": "boom"}
    ]);
    serveGoldenBackend(backend);
    final (d, reading) = lamp();
    final toggle = await mountToggle(tester, d);

    await tester.runAsync(toggle);
    await tester.pump();

    expect(sentFunctionIds(backend), [setOff], reason: "no read-back after a refused command");
    expect(toasts, ["Error running command: boom"]);
    expect(reading.transitioning, isFalse);
    expect(reading.value, isTrue);
    expect(find.byType(DelayedCircularProgressIndicator), findsNothing);
  });

  testWidgets("a read-back that is not a list is taken as the value", (tester) async {
    final backend = FakeBackend();
    // Not a list: taken whole, as performDeviceStateAction does.
    backend.serveJson("POST", _batch, 200, [
      {"status_code": 200, "message": 5}
    ]);
    serveGoldenBackend(backend);
    final (d, reading) = lamp();
    final toggle = await mountToggle(tester, d);

    Object? error;
    await tester.runAsync(() async {
      try {
        await toggle();
      } catch (e) {
        error = e;
      }
    });
    await tester.pump();

    expect(error, isNull);
    expect(reading.transitioning, isFalse);
    expect(reading.value, 5);
  });

  testWidgets("a device type without the control toasts and sends nothing", (tester) async {
    final backend = FakeBackend();
    serveGoldenBackend(backend);
    final (d, reading) = lamp(withControls: false);
    final toggle = await mountToggle(tester, d);

    await tester.runAsync(toggle);
    await tester.pump();

    expect(toasts, ["Found no controlling service, check device type!"]);
    expect(backend.requests, isEmpty);
    expect(reading.transitioning, isFalse);
  });

  testWidgets("the shared action resolves a reading's control and refreshes the reading", (tester) async {
    final backend = FakeBackend();
    backend.serveJson("POST", _batch, 200, [
      {"status_code": 200, "message": [false]}
    ]);
    serveGoldenBackend(backend);
    AppState().platformFunctions[setOff] = PlatformFunction(setOff, "setOff", "", "Switch off");
    final (d, reading) = lamp();
    await pumpGolden(tester, const Scaffold(), dark: false);
    final context = tester.element(find.byType(Scaffold));

    await tester.runAsync(() => performDeviceStateAction(
          context: context,
          connectionStatus: d.connection_state,
          element: reading,
          states: d.states,
          isGroup: false,
          setState: (fn) => fn(),
          notifyEntity: d.notifyStateChanged,
        ));

    expect(sentFunctionIds(backend), [setOff, onOff]);
    expect(reading.value, isFalse);
    expect(d.states.map((s) => s.transitioning), everyElement(isFalse));
    expect(toasts, isEmpty);
  });
}
