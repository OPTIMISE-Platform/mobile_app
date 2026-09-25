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
import 'package:mobile_app/widgets/tabs/sensors/reorder_page.dart';

/// Opens the reorder page over ['A', 'B', 'C'], drags the handle at [index]
/// by [offset], taps Done and returns the resulting order.
Future<List<String>?> _reorderAndDone(
    WidgetTester tester, int index, Offset offset) async {
  List<String>? result;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () async {
          result = await reorderItems<String>(
            context,
            title: 'Reorder',
            items: const ['A', 'B', 'C'],
            label: (s) => s,
          );
        },
        child: const Text('open'),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  // A large overshoot rather than a measured tile height: it lands the drag
  // at the first or last slot regardless of the row's rendered size.
  await tester.drag(find.byIcon(Icons.drag_handle).at(index), offset);
  await tester.pumpAndSettle();

  await tester.tap(find.text('Done'));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('dragging the first item down moves it to the end',
      (tester) async {
    final result = await _reorderAndDone(tester, 0, const Offset(0, 1000));
    expect(result, ['B', 'C', 'A']);
  });

  testWidgets('dragging the last item up moves it to the start',
      (tester) async {
    final result = await _reorderAndDone(tester, 2, const Offset(0, -1000));
    expect(result, ['C', 'A', 'B']);
  });
}
