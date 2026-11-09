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
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/widgets/tabs/shared/value_change.dart';

import 'golden_helper.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  Widget page(Object? value, ValueChangeStyle style) => MaterialApp(
        home: Center(child: ValueChange(value: value, style: style, child: Text('$value W'))),
      );

  double flashAlpha(WidgetTester tester) {
    final box = tester.widget<DecoratedBox>(
        find.descendant(of: find.byType(ValueChange), matching: find.byType(DecoratedBox)).first);
    return ((box.decoration as BoxDecoration).color?.a ?? 0);
  }

  testWidgets('flash tints the value on a change and fades out, not on the first value', (tester) async {
    await tester.pumpWidget(page(null, ValueChangeStyle.flash));
    await tester.pumpWidget(page(10, ValueChangeStyle.flash));
    await tester.pump();
    expect(flashAlpha(tester), 0, reason: 'a first value is not a change');

    await tester.pumpWidget(page(12, ValueChangeStyle.flash));
    await tester.pump();
    expect(flashAlpha(tester), greaterThan(0.3));
    await tester.pump(const Duration(milliseconds: 1600));
    expect(flashAlpha(tester), 0);

    await tester.pumpWidget(page(12, ValueChangeStyle.flash));
    await tester.pump();
    expect(flashAlpha(tester), 0, reason: 'the same value again is not a change');
  });

  testWidgets('arrow points the way the value went and fades out', (tester) async {
    await tester.pumpWidget(page(10, ValueChangeStyle.arrow));
    double opacity() => tester.widget<Opacity>(find.byType(Opacity)).opacity;
    expect(opacity(), 0);

    await tester.pumpWidget(page(12, ValueChangeStyle.arrow));
    await tester.pump();
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    expect(opacity(), greaterThan(0.9));

    await tester.pumpWidget(page(7, ValueChangeStyle.arrow));
    await tester.pump();
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(opacity(), 0);
  });

  testWidgets('slide shows old and new value while the new one comes in', (tester) async {
    await tester.pumpWidget(page(10, ValueChangeStyle.slide));
    await tester.pumpWidget(page(12, ValueChangeStyle.slide));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('10 W'), findsOneWidget);
    expect(find.text('12 W'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('10 W'), findsNothing);
    expect(find.text('12 W'), findsOneWidget);
  });

  testWidgets('without a style the setting decides, flash until one is chosen', (tester) async {
    expect(Settings.getValueChangeStyle(), ValueChangeStyle.flash);
    // Hive writes complete only outside the fake zone (docs/testing.md).
    await tester.runAsync(() => Settings.setValueChangeStyle(ValueChangeStyle.slide));
    expect(Settings.getValueChangeStyle(), ValueChangeStyle.slide);
    expect(ValueChange(value: 1, child: const SizedBox()).style, ValueChangeStyle.slide);
    await tester.runAsync(() => Settings.setValueChangeStyle(ValueChangeStyle.flash));
  });

  test('an unknown stored style falls back to flash', () {
    expect(ValueChangeStyle.parse('color'), ValueChangeStyle.flash);
    expect(ValueChangeStyle.parse(null), ValueChangeStyle.flash);
    expect(ValueChangeStyle.parse('arrow'), ValueChangeStyle.arrow);
  });
}
