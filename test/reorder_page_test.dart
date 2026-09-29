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
import 'package:mobile_app/widgets/shared/grouped_list_tile.dart';
import 'package:mobile_app/widgets/shared/slice_position.dart';
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

/// Opens the reorder page over ['A', 'B', 'C'] and hands what it returns to
/// [onResult] once it is closed.
Future<void> _openReorderPage(WidgetTester tester,
    void Function(List<String>?) onResult) async {
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () async {
          onResult(await reorderItems<String>(
            context,
            title: 'Reorder',
            items: const ['A', 'B', 'C'],
            label: (s) => s,
          ));
        },
        child: const Text('open'),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

SlicePosition _positionOfRow(WidgetTester tester, String label) => tester
    .widget<GroupedListTile>(find.ancestor(
        of: find.text(label), matching: find.byType(GroupedListTile)))
    .position;

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

  testWidgets('lifting the first row rounds the top of the new first row',
      (tester) async {
    List<String>? result;
    await _openReorderPage(tester, (r) => result = r);
    expect(_positionOfRow(tester, 'B'), SlicePosition.middle);

    final gesture = await tester
        .startGesture(tester.getCenter(find.byIcon(Icons.drag_handle).at(0)));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 5));
    await tester.pump(const Duration(milliseconds: 300));

    expect(_positionOfRow(tester, 'B'), SlicePosition.first);
    expect(_positionOfRow(tester, 'C'), SlicePosition.last);

    await gesture.moveBy(const Offset(0, 1000));
    await tester.pump();
    await gesture.up();
    // Mid drop animation the rows keep the corners they had while lifted.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(_positionOfRow(tester, 'B'), SlicePosition.first);
    await tester.pumpAndSettle();

    expect(_positionOfRow(tester, 'B'), SlicePosition.first);
    expect(_positionOfRow(tester, 'C'), SlicePosition.middle);
    expect(_positionOfRow(tester, 'A'), SlicePosition.last);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(result, ['B', 'C', 'A']);
  });

  testWidgets('lifting the last row rounds the bottom of the new last row',
      (tester) async {
    await _openReorderPage(tester, (_) {});

    final gesture = await tester
        .startGesture(tester.getCenter(find.byIcon(Icons.drag_handle).at(2)));
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -5));
    await tester.pump(const Duration(milliseconds: 300));

    expect(_positionOfRow(tester, 'A'), SlicePosition.first);
    expect(_positionOfRow(tester, 'B'), SlicePosition.last);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a row dropped where it was restores the resting positions',
      (tester) async {
    await _openReorderPage(tester, (_) {});

    final gesture = await tester
        .startGesture(tester.getCenter(find.byIcon(Icons.drag_handle).at(0)));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -20));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_positionOfRow(tester, 'B'), SlicePosition.first);

    await gesture.up();
    await tester.pumpAndSettle();

    expect(_positionOfRow(tester, 'A'), SlicePosition.first);
    expect(_positionOfRow(tester, 'B'), SlicePosition.middle);
    expect(_positionOfRow(tester, 'C'), SlicePosition.last);
  });

  testWidgets('a drop in place past the row below restores the positions',
      (tester) async {
    List<String>? result;
    await _openReorderPage(tester, (r) => result = r);

    final gesture = await tester
        .startGesture(tester.getCenter(find.byIcon(Icons.drag_handle).at(0)));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    // Far enough down for the insertion index to become 1 (below the lifted
    // row), the other way of ending on the original slot.
    await gesture.moveBy(const Offset(0, 15));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -10));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_positionOfRow(tester, 'B'), SlicePosition.first);

    await gesture.up();
    // Already back to the resting corners mid drop animation; the proxy's
    // removal at its end would restore them too, just later.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(_positionOfRow(tester, 'B'), SlicePosition.middle);
    await tester.pumpAndSettle();

    expect(_positionOfRow(tester, 'A'), SlicePosition.first);
    expect(_positionOfRow(tester, 'B'), SlicePosition.middle);
    expect(_positionOfRow(tester, 'C'), SlicePosition.last);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(result, ['A', 'B', 'C']);
  });

  testWidgets('a cancelled drag restores the resting positions',
      (tester) async {
    await _openReorderPage(tester, (_) {});

    final gesture = await tester
        .startGesture(tester.getCenter(find.byIcon(Icons.drag_handle).at(0)));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 5));
    await tester.pump(const Duration(milliseconds: 300));
    expect(_positionOfRow(tester, 'B'), SlicePosition.first);

    await gesture.cancel();
    await tester.pumpAndSettle();

    expect(_positionOfRow(tester, 'A'), SlicePosition.first);
    expect(_positionOfRow(tester, 'B'), SlicePosition.middle);
    expect(_positionOfRow(tester, 'C'), SlicePosition.last);
  });
}
