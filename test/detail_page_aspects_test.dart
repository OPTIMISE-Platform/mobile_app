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
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/aspect.dart';
import 'package:mobile_app/models/device_class.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/models/function.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/detail_page.dart';

import 'golden_helper.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
  });

  DeviceInstance device() {
    final lamp = DeviceClass("class-1", "Lamps", "");
    AppState().deviceClasses[lamp.id] = lamp;
    AppState().deviceTypes["device-type-1"] = DeviceType("device-type-1", "Smart Lamp", "", lamp.id, [], null);
    for (final a in [
      Aspect("air", "Air", [Aspect("inside", "Inside", null), Aspect("outside", "Outside", null)]),
      Aspect("device", "Device", null),
      Aspect("lamp", "Lamp", null),
    ]) {
      AppState().aspects[a.id] = a;
    }
    final d = DeviceInstance("device-1", "device-1-local", "Living room lamp", null, "device-type-1", false, "owner-1",
        "Living room lamp", DeviceConnectionStatus.online);
    AppState().devices.add(d);
    return d;
  }

  void addFunction(String id, String displayName) =>
      AppState().platformFunctions[id] = PlatformFunction(id, id, "", displayName);

  DeviceState state(DeviceInstance d, String functionId, List<String> aspectIds, bool controlling, {dynamic value}) =>
      DeviceState(value, "service-1", "group-1", functionId, null, controlling, null, null, d.id, "path", "group",
          aspectIds: aspectIds);

  testWidgets("two readings sharing their first aspect get a row each, named by all aspects", (tester) async {
    final d = device();
    addFunction("temperature", "Temperature");
    d.states
      ..add(state(d, "temperature", ["air", "inside"], false, value: 21.5))
      ..add(state(d, "temperature", ["air", "outside"], false, value: 4.0));

    await pumpGolden(tester, DetailPage(d, null), dark: false);

    expect(tester.takeException(), isNull);
    expect(find.text("Temperature"), findsNWidgets(2));
    expect(find.text("Air, Inside"), findsOneWidget);
    expect(find.text("Air, Outside"), findsOneWidget);
    // A row key built from the first aspect alone is the same for both rows,
    // which SectionedListView can only resolve by position ("key#1").
    final rowKeys = tester
        .widgetList(find.byWidgetPredicate((w) => w.key is ValueKey<(String, String)>))
        .map((w) => (w.key! as ValueKey<(String, String)>).value.$2)
        .toList();
    expect(rowKeys, hasLength(2));
    expect(rowKeys, everyElement(isNot(contains("#"))));
  });

  testWidgets("a long press finds the timestamp on a subset of the reading's aspects", (tester) async {
    final toasts = <String>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = MethodChannel('PonnamKarthik/fluttertoast');
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == "showToast") toasts.add((call.arguments as Map)["msg"] as String);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, (call) async => true));

    final d = device();
    final timestamp = dotenv.env['FUNCTION_GET_TIMESTAMP']!;
    addFunction("temperature", "Temperature");
    addFunction(timestamp, "Timestamp");
    d.states
      ..add(state(d, "temperature", ["air", "inside"], false, value: 21.5))
      ..add(state(d, timestamp, ["air"], false));

    await pumpGolden(tester, DetailPage(d, null), dark: false);
    // After the page's own value load, which fails without a backend.
    d.states.last.value = "2026-09-29T08:30:00Z";
    toasts.clear();
    await tester.longPress(find.text("Temperature"));
    await tester.pump();

    expect(toasts, hasLength(1));
    expect(toasts.single, contains("2026"));
    // Lets the toast plugin's own timer run out.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets("a reading pairs with the unique control on a subset of its aspects", (tester) async {
    final d = device();
    final get = dotenv.env['FUNCTION_GET_ON_OFF_STATE']!;
    final on = dotenv.env['FUNCTION_SET_ON_STATE']!;
    final off = dotenv.env['FUNCTION_SET_OFF_STATE']!;
    addFunction(get, "Power state");
    addFunction(on, "Switch on");
    addFunction(off, "Switch off");
    // "device" sorts first, so the first aspect of the reading is not the
    // control's: only the subset rule pairs them.
    d.states
      ..add(state(d, get, ["device", "lamp"], false, value: true))
      ..add(state(d, on, ["lamp"], true))
      ..add(state(d, off, ["lamp"], true));

    await pumpGolden(tester, DetailPage(d, null), dark: false);
    // After the page's own value load, which fails without a backend: an
    // unknown state keeps its controls as rows of their own.
    d.states.first.value = true;
    d.notifyStateChanged();
    await tester.pump();

    expect(find.text("Power state"), findsOneWidget);
    // Paired controls are folded into the reading's row instead of listed.
    expect(find.text("Switch on"), findsNothing);
    expect(find.text("Switch off"), findsNothing);
  });

  testWidgets("a control that picks no reading keeps a row of its own", (tester) async {
    final d = device();
    final get = dotenv.env['FUNCTION_GET_ON_OFF_STATE']!;
    final on = dotenv.env['FUNCTION_SET_ON_STATE']!;
    final off = dotenv.env['FUNCTION_SET_OFF_STATE']!;
    addFunction(get, "Power state");
    addFunction(on, "Switch on");
    addFunction(off, "Switch off");
    // Both readings contain the controls' aspect and are equally small, so
    // the controls cannot tell which one they switch.
    d.states
      ..add(state(d, get, ["air", "inside"], false, value: true))
      ..add(state(d, get, ["air", "outside"], false, value: true))
      ..add(state(d, on, ["air"], true))
      ..add(state(d, off, ["air"], true));

    await pumpGolden(tester, DetailPage(d, null), dark: false);
    // After the page's own value load, which fails without a backend.
    d.states[0].value = true;
    d.states[1].value = true;
    d.notifyStateChanged();
    await tester.pump();

    expect(find.text("Power state"), findsNWidgets(2));
    expect(find.text("Switch on"), findsOneWidget);
    expect(find.text("Switch off"), findsOneWidget);
  });

  testWidgets("a control on fewer aspects than a reading with an exact control keeps its own row", (tester) async {
    final d = device();
    final get = dotenv.env['FUNCTION_GET_ON_OFF_STATE']!;
    final on = dotenv.env['FUNCTION_SET_ON_STATE']!;
    final off = dotenv.env['FUNCTION_SET_OFF_STATE']!;
    addFunction(get, "Power state");
    addFunction(on, "Switch on");
    addFunction(off, "Switch off");
    d.states
      ..add(state(d, get, ["device", "lamp"], false, value: true))
      ..add(state(d, on, ["device", "lamp"], true))
      ..add(state(d, off, ["device", "lamp"], true))
      ..add(state(d, on, ["device"], true));

    await pumpGolden(tester, DetailPage(d, null), dark: false);
    // After the page's own value load, which fails without a backend.
    d.states.first.value = true;
    d.notifyStateChanged();
    await tester.pump();

    expect(find.text("Power state"), findsOneWidget);
    expect(find.text("Switch off"), findsNothing);
    expect(find.text("Switch on"), findsOneWidget, reason: "the control on [device] alone");
  });

  testWidgets("a group control on its aspects and the one on its device class are named apart", (tester) async {
    final thermostat = DeviceClass("class-thermostat", "Thermostat", "");
    AppState().deviceClasses[thermostat.id] = thermostat;
    AppState().aspects["target"] = Aspect("target", "Target", null);
    AppState().aspects["reading"] = Aspect("reading", "Reading", null);
    const setTemperature = "$controllingFunctionPrefix:set-temperature";
    addFunction(setTemperature, "Set-Temperature");
    // A controlling function yields its device-class criterion and, since
    // device-repository combines it with aspects, one per aspect.
    final criteria = [
      {"aspect_id": "", "device_class_id": thermostat.id, "function_id": setTemperature, "interaction": "request"},
      {"aspect_id": "target", "aspect_ids": ["target"], "device_class_id": "", "function_id": setTemperature, "interaction": "request"},
      {"aspect_id": "reading", "aspect_ids": ["reading"], "device_class_id": "", "function_id": setTemperature, "interaction": "request"},
    ].map(DeviceGroupCriteria.fromJson).toList();
    // The page waits until the members are among the loaded devices; group
    // member ids are at least 57 characters long.
    final memberId = "urn:infai:ses:device:${'0' * 36}";
    AppState().devices.add(DeviceInstance(memberId, "thermostat-local", "Hall thermostat", null, "thermostat", false,
        "owner-1", "Hall thermostat", DeviceConnectionStatus.online));
    final group = DeviceGroup("group-1", "Thermostats", criteria, "", [memberId], null)..prepareStates();

    await pumpGolden(tester, DetailPage(null, group), dark: false);

    expect(find.text("Set-Temperature"), findsNWidgets(3));
    expect(find.text("Thermostat"), findsOneWidget);
    expect(find.text("Target"), findsOneWidget);
    expect(find.text("Reading"), findsOneWidget);
    expect(find.text("MISSING_ASPECT_NAME"), findsNothing);
  });
}
