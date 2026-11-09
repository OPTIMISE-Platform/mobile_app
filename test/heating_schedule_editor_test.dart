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
import 'package:mobile_app/widgets/tabs/smart-services/heating_schedule_editor.dart';
import 'package:mobile_app/widgets/tabs/smart-services/heating_schedule_model.dart';

void main() {
  main2();

  testWidgets("the editor adds, edits and rejects windows and reports the plan", (tester) async {
    final formKey = GlobalKey<FormState>();
    HeatingSchedule? last;
    var calls = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: HeatingScheduleEditor(
              initial: const HeatingSchedule([], 17),
              onChanged: (p) {
                last = p;
                calls++;
              },
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text("Add time window"));
    await tester.pump();
    expect(last!.serialise(), '{"windows":[{"weekdays":[0,1,2,3,4],"from":"06:00","to":"08:00","temperature":20}]}');
    expect(last!.setback, 17);

    await tester.tap(find.byIcon(Icons.add).first); // temperature of the window, +0.5
    await tester.tap(find.widgetWithText(FilterChip, "Fri"));
    await tester.tap(find.widgetWithText(FilterChip, "Sat"));
    await tester.pump();
    expect(last!.serialise(), '{"windows":[{"weekdays":[0,1,2,3,5],"from":"06:00","to":"08:00","temperature":20.5}]}');

    await tester.tap(find.byIcon(Icons.add).last); // setback
    await tester.pump();
    expect(last!.setback, 18);

    // all weekdays off: invalid, reported as null and as a form error
    for (final d in ["Mon", "Tue", "Wed", "Thu", "Sat"]) {
      await tester.tap(find.widgetWithText(FilterChip, d));
    }
    await tester.pump();
    expect(last, isNull);
    expect(find.text("Pick at least one weekday."), findsOneWidget);
    expect(formKey.currentState!.validate(), isFalse);

    await tester.tap(find.widgetWithText(FilterChip, "Sun"));
    await tester.pump();
    expect(last, isNotNull);
    expect(formKey.currentState!.validate(), isTrue);

    final before = calls;
    await tester.tap(find.byIcon(Icons.delete));
    await tester.pump();
    expect(calls, before + 1);
    expect(last!.windows, isEmpty);
  });
}

Future<HeatingSchedule?> _afterAnEdit(WidgetTester tester, HeatingSchedule initial, {bool showSetback = true}) async {
  HeatingSchedule? last = initial;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: HeatingScheduleEditor(initial: initial, showSetback: showSetback, onChanged: (p) => last = p),
      ),
    ),
  ));
  // an edit elsewhere in the list makes the editor report the whole plan
  await tester.tap(find.text("Add time window"));
  await tester.pump();
  await tester.tap(find.byIcon(Icons.delete).last);
  await tester.pump();
  return last;
}

void main2() {
  for (final w in [
    '{"from":"18:00","to":"24:00","temperature":20}',
    '{"from":"00:00","to":"24:00","temperature":20}',
    '{"from":"24:00","to":"24:00","temperature":20}',
    '{"from":"24:00","to":"06:00","temperature":20}',
  ]) {
    testWidgets("the window $w goes through the editor unchanged", (tester) async {
      final text = HeatingSchedule.parse('{"windows":[$w]}', 17).serialise();
      final out = await _afterAnEdit(tester, HeatingSchedule.parse(text, 17));
      expect(out!.serialise(), text);
    });
  }

  testWidgets("stored values out of range or off the grid stay until the user changes them", (tester) async {
    final out = await _afterAnEdit(tester, HeatingSchedule.parse('{"windows":[{"from":"06:00","to":"08:00","temperature":35}]}', 3));
    expect(out!.setback, 3);
    expect(out.windows.single.temperature, 35);
  });

  testWidgets("the buttons snap to the 0.5 grid without float noise", (tester) async {
    HeatingSchedule? last;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: HeatingScheduleEditor(
            initial: HeatingSchedule.parse('{"windows":[{"from":"06:00","to":"08:00","temperature":15.6}]}', 17),
            onChanged: (p) => last = p,
          ),
        ),
      ),
    ));
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pump();
    expect(last!.windows.single.temperature, 16.0);
    await tester.tap(find.byIcon(Icons.remove).first);
    await tester.tap(find.byIcon(Icons.remove).first);
    await tester.pump();
    expect(last!.windows.single.temperature, 15.0);
  });
}
