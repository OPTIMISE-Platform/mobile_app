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
import 'package:mobile_app/widgets/shared/multi_select_field.dart';

void main() {
  // The same device offered in two groups, as the smart-service backend does.
  const options = [
    MultiSelectOption("Wallbox", group: "Devices"),
    MultiSelectOption("Wallbox", group: "Groups"),
    MultiSelectOption("Heat pump", group: "Devices"),
  ];

  Future<List<int>?> pickFirst(WidgetTester tester) async {
    List<int>? changed;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MultiSelectField(
          options: options,
          selected: const [],
          emptyLabel: "Chargers",
          onChanged: (x) => changed = x,
        ),
      ),
    ));
    await tester.tap(find.text("Chargers"));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, "Wallbox").first);
    await tester.pump();
    await tester.tap(find.text("OK"));
    await tester.pumpAndSettle();
    return changed;
  }

  testWidgets("ticking one of two equally labelled options selects only it",
      (tester) async {
    expect(await pickFirst(tester), [0]);
  });

  testWidgets("lists options under their group", (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MultiSelectField(
          options: options,
          selected: const [],
          emptyLabel: "Chargers",
          onChanged: (_) {},
        ),
      ),
    ));
    await tester.tap(find.text("Chargers"));
    await tester.pumpAndSettle();
    final labels = tester
        .widgetList<Text>(find.descendant(
            of: find.byType(ListView), matching: find.byType(Text)))
        .map((t) => t.data)
        .toList();
    expect(labels, ["Devices", "Wallbox", "Heat pump", "Groups", "Wallbox"]);
  });
}
