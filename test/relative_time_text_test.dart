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
import 'package:mobile_app/widgets/tabs/shared/state_time.dart';

import 'golden_helper.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  Future<double> widthOf(WidgetTester tester, String phrase, {String prefix = ''}) async {
    await tester.pumpWidget(MaterialApp(
      home: Center(child: relativeTimeText(phrase, prefix: prefix, key: const Key('t'))),
    ));
    return tester.getSize(find.byKey(const Key('t'))).width;
  }

  testWidgets('the phrases of one unit are equally wide, whatever the count', (tester) async {
    for (final unit in [
      ['< 30 seconds ago', '30 seconds ago', '41 seconds ago', '59 seconds ago'],
      ['1 min ago', '7 min ago', '11 min ago', '59 min ago'],
      ['1 h ago', '9 h ago', '23 h ago'],
    ]) {
      final widths = [for (final phrase in unit) await widthOf(tester, phrase)];
      expect(widths.toSet(), hasLength(1), reason: '$unit: $widths');
    }
    // With a prefix as in the detail page header too.
    expect(await widthOf(tester, '< 30 seconds ago', prefix: 'Last message '),
        await widthOf(tester, '42 seconds ago', prefix: 'Last message '));
  });

  testWidgets('screen readers and finders get the phrase without the reserved room', (tester) async {
    await tester.pumpWidget(MaterialApp(home: relativeTimeText('31 seconds ago', prefix: 'Last message ')));
    expect(findShownText('Last message 31 seconds ago'), findsOneWidget);
    expect(tester.getSemantics(find.byType(Text)).label, 'Last message 31 seconds ago');
  });

  testWidgets('a phrase without a count is plain text', (tester) async {
    await tester.pumpWidget(MaterialApp(home: relativeTimeText('yesterday 14:02')));
    expect(find.text('yesterday 14:02'), findsOneWidget);
  });
}
