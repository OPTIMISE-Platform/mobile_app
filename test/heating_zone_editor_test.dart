/*
 * Copyright (c) 2026 InfAI (CC SES)
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
import 'package:mobile_app/widgets/tabs/smart-services/heating_schedule_model.dart';
import 'package:mobile_app/widgets/tabs/smart-services/heating_zone_editor.dart';

const _a = HeatingThermostat("urn:infai:ses:device:aaa", "Thermostat aaa");
const _b = HeatingThermostat("urn:infai:ses:device:bbb", "Thermostat bbb");
const _c = HeatingThermostat("urn:infai:ses:device:ccc", "Thermostat ccc");

const _w = '{"weekdays":[0,1,2,3,4],"from":"06:00","to":"20:00","temperature":20}';

class _Harness {
  HeatingPlan? last;
  var calls = 0;
  final formKey = GlobalKey<FormState>();
  final thermostats = ValueNotifier<List<HeatingThermostat>>([_a, _b, _c]);

  Future<void> pump(WidgetTester tester, String plan, {double setback = 17, bool showSetback = true}) async {
    tester.view.physicalSize = const Size(600, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: ValueListenableBuilder(
              valueListenable: thermostats,
              builder: (_, list, __) => HeatingZoneEditor(
                initial: HeatingPlan.parse(plan, setback),
                thermostats: list,
                showSetback: showSetback,
                onChanged: (p) {
                  last = p;
                  calls++;
                },
              ),
            ),
          ),
        ),
      ),
    ));
  }
}

final _zoneDelete = find.byWidgetPredicate((w) => w is IconButton && w.tooltip == "Delete zone");

Finder _box(String label) => find.widgetWithText(CheckboxListTile, label);

void main() {
  const twoZones = '{"zones":[{"name":"Bad","devices":["urn:infai:ses:device:bbb"],"windows":[$_w]},{"name":"Rest","windows":[]}]}';

  testWidgets("a thermostat is in one zone only: it is disabled elsewhere and shows the zone", (tester) async {
    final h = _Harness();
    await h.pump(tester, '{"zones":[{"name":"Bad","devices":["urn:infai:ses:device:bbb"],"windows":[]},{"name":"Flur","devices":[],"windows":[]}]}');

    // Bad holds bbb; Flur sees it disabled with the zone name, and the other two enabled
    final flurB = tester.widget<CheckboxListTile>(_box("Thermostat bbb").last);
    expect(flurB.onChanged, isNull);
    expect(find.text("In Bad"), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(_box("Thermostat aaa").last).onChanged, isNotNull);

    await tester.tap(_box("Thermostat aaa").last);
    await tester.pump();
    expect(h.last!.serialise(),
        '{"zones":[{"name":"Bad","devices":["urn:infai:ses:device:bbb"],"windows":[]},{"name":"Flur","devices":["urn:infai:ses:device:aaa"],"windows":[]}]}');
    // now Bad sees aaa disabled
    expect(find.text("In Flur"), findsOneWidget);

    await tester.tap(_box("Thermostat bbb").first);
    await tester.pump();
    expect(h.last!.serialise(), contains('"devices":[]'));
    expect(find.text("In Bad"), findsNothing);
  });

  testWidgets("only one zone may take all other thermostats; its checkboxes are hidden", (tester) async {
    final h = _Harness();
    await h.pump(tester, twoZones);

    // zone 2 is the rest zone: no checkboxes of its own (three in zone 1 only)
    expect(find.byType(CheckboxListTile), findsNWidgets(3));
    final switches = find.widgetWithText(Row, "All other thermostats");
    expect(switches, findsNWidgets(2));
    expect(tester.widget<Switch>(find.descendant(of: switches.first, matching: find.byType(Switch))).onChanged, isNull);
    expect(tester.widget<Switch>(find.descendant(of: switches.last, matching: find.byType(Switch))).onChanged, isNotNull);

    // turning it off in zone 2 frees the toggle in zone 1 and shows zone 2's checkboxes
    await tester.tap(find.descendant(of: switches.last, matching: find.byType(Switch)));
    await tester.pump();
    expect(find.byType(CheckboxListTile), findsNWidgets(6));
    expect(tester.widget<Switch>(find.descendant(of: switches.first, matching: find.byType(Switch))).onChanged, isNotNull);
    // no zone has a rest toggle on any more, Rest has no thermostat: still valid because Bad has one
    expect(h.last, isNotNull);
  });

  testWidgets("zone names must be unique after trimming", (tester) async {
    final h = _Harness();
    await h.pump(tester, twoZones);
    expect(h.formKey.currentState!.validate(), isTrue);

    await tester.enterText(find.widgetWithText(TextField, "Rest"), " Bad ");
    await tester.pump();
    expect(h.last, isNull);
    expect(find.text("Zone names must be unique."), findsOneWidget);
    expect(h.formKey.currentState!.validate(), isFalse);

    await tester.enterText(find.widgetWithText(TextField, " Bad "), "Rest");
    await tester.pump();
    expect(h.last, isNotNull);
  });

  testWidgets("add zone appends an empty zone with the default window, delete keeps at least one", (tester) async {
    final h = _Harness();
    await h.pump(tester, '{"windows":[]}');
    expect(_zoneDelete, findsOneWidget);
    expect(tester.widget<IconButton>(_zoneDelete).onPressed, isNull);

    await tester.tap(find.text("Add zone"));
    await tester.pump();
    expect(h.last!.serialise(),
        '{"zones":[{"name":"Alle","windows":[]},{"name":"Zone 2","devices":[],"windows":[$_w]}]}');

    await tester.tap(_zoneDelete.last);
    await tester.pump();
    // one rest zone without own setback again: the legacy shape
    expect(h.last!.serialise(), '{"windows":[]}');
    expect(tester.widget<IconButton>(_zoneDelete).onPressed, isNull);
  });

  testWidgets("an own setback is written with the zone, the global one is not", (tester) async {
    final h = _Harness();
    await h.pump(tester, '{"windows":[]}');
    expect(find.text("17 °C"), findsOneWidget);

    await tester.tap(find.byType(Switch).last); // the plan has no window, so the last switch is the own setback
    await tester.pump();
    expect(h.last!.serialise(), '{"zones":[{"name":"Alle","windows":[],"setback":17}]}');

    await tester.tap(find.byTooltip("Increase").last);
    await tester.pump();
    expect(h.last!.serialise(), '{"zones":[{"name":"Alle","windows":[],"setback":18}]}');
    expect(h.last!.setback, 17);
  });

  testWidgets("a plan without any selected thermostat is invalid, also when the selection changes later", (tester) async {
    final h = _Harness();
    await h.pump(tester, '{"zones":[{"name":"X","devices":["urn:infai:ses:device:ddd"],"windows":[]}]}');
    expect(h.calls, 0);
    expect(h.formKey.currentState!.validate(), isFalse);
    expect(find.text("No zone has a selected thermostat."), findsOneWidget);

    h.thermostats.value = [_a, const HeatingThermostat("urn:infai:ses:device:ddd", "Thermostat ddd")];
    await tester.pump();
    await tester.pump();
    expect(h.formKey.currentState!.validate(), isTrue);
    expect(h.last, isNotNull);
    expect(h.last!.serialise(), '{"zones":[{"name":"X","devices":["urn:infai:ses:device:ddd"],"windows":[]}]}');
  });

  testWidgets("a thermostat stored in two zones can be unticked in either", (tester) async {
    final h = _Harness();
    await h.pump(tester,
        '{"zones":[{"name":"X","devices":["urn:infai:ses:device:aaa"],"windows":[]},{"name":"Y","devices":["urn:infai:ses:device:aaa"],"windows":[]}]}');
    expect(find.text("Zone names must be unique."), findsNothing);
    expect(find.textContaining("is in X and Y"), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(_box("Thermostat aaa").first).onChanged, isNotNull);
    expect(tester.widget<CheckboxListTile>(_box("Thermostat aaa").last).onChanged, isNotNull);

    await tester.tap(_box("Thermostat aaa").last);
    await tester.pump();
    expect(h.last!.serialise(),
        '{"zones":[{"name":"X","devices":["urn:infai:ses:device:aaa"],"windows":[]},{"name":"Y","devices":[],"windows":[]}]}');
  });

  testWidgets("a new own setback starts at the global one, clamped; the global one can change from outside", (tester) async {
    final h = _Harness();
    await h.pump(tester, '{"windows":[]}', setback: 3, showSetback: false);
    await tester.tap(find.byType(Switch).last);
    await tester.pump();
    expect(h.last!.serialise(), '{"zones":[{"name":"Alle","windows":[],"setback":5}]}');

    // the global setback changes in the form; an own setback switched on afterwards starts there
    await tester.tap(find.byType(Switch).last);
    await tester.pump();
    await h.pump(tester, '{"windows":[]}', setback: 21, showSetback: false);
    await tester.tap(find.byType(Switch).last);
    await tester.pump();
    expect(h.last!.serialise(), '{"zones":[{"name":"Alle","windows":[],"setback":21}]}');
  });

  testWidgets("the lone rest zone with an empty name is written as the legacy shape, a named one is not", (tester) async {
    final h = _Harness();
    await h.pump(tester, '{"windows":[$_w]}');
    await tester.enterText(find.widgetWithText(TextField, "Alle"), "");
    await tester.pump();
    expect(h.last!.serialise(), '{"windows":[$_w]}');
    await tester.enterText(find.byType(TextField).first, "Haus");
    await tester.pump();
    expect(h.last!.serialise(), '{"zones":[{"name":"Haus","windows":[$_w]}]}');
  });

  testWidgets("the edit page cannot save a stored plan the editor shows as invalid", (tester) async {
    Future<void> show(String plan) => tester.pumpWidget(MaterialApp(
        home: HeatingZonesEditPage(initial: HeatingPlan.parse(plan, 17), thermostats: const [_a])));
    VoidCallback? save() => tester.widget<TextButton>(find.widgetWithText(TextButton, "Save")).onPressed;

    await show('{"zones":[{"name":"X","devices":["urn:infai:ses:device:ddd"],"windows":[]}]}');
    expect(save(), isNull);
    expect(find.text("No zone has a selected thermostat."), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await show('{"windows":[]}');
    expect(save(), isNotNull);
  });
}
