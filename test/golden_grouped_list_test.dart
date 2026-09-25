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

@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/widgets/shared/grouped_list_tile.dart';
import 'package:mobile_app/widgets/shared/section_list_header.dart';
import 'package:mobile_app/widgets/shared/slice_position.dart';

import 'golden_helper.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
  });

  Widget screen() => Scaffold(
        body: ListView(
          children: [
            const SectionListHeader("Section A"),
            const GroupedListTile(
              position: SlicePosition.only,
              child: ListTile(title: Text("Solo row")),
            ),
            const SectionListHeader("Section B"),
            GroupedListTile(
              position: SlicePosition.first,
              hairlineInset: GroupedListTile.insetIconLeading,
              child: ListTile(
                leading: const Icon(Icons.lightbulb_outline),
                title: const Text("Row 1"),
                trailing: Switch(value: true, onChanged: (_) {}),
              ),
            ),
            const GroupedListTile(
              position: SlicePosition.middle,
              hairlineInset: GroupedListTile.insetNoLeading,
              child: ListTile(title: Text("Row 2")),
            ),
            const GroupedListTile(
              position: SlicePosition.last,
              child: ListTile(title: Text("Row 3")),
            ),
          ],
        ),
      );

  for (final dark in [false, true]) {
    final suffix = dark ? "dark" : "light";

    testWidgets("grouped list sections ($suffix)", (tester) async {
      await pumpGolden(tester, screen(), dark: dark);
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile("goldens/grouped_list_$suffix.png"));
    });
  }
}
