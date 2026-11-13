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
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/widgets/settings/settings.dart';

import 'golden_helper.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(resetAppStateForGolden);

  testWidgets("sharing the debug information anchors the sheet at its button",
      (tester) async {
    final shared = <Map<Object?, Object?>>[];
    const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(shareChannel,
        (call) async {
      shared.add(call.arguments as Map<Object?, Object?>);
      return "";
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, null));

    await pumpGolden(tester, const Settings(), dark: false);
    await tester.ensureVisible(find.text("Show Debug Information"));
    await tester.tap(find.text("Show Debug Information"));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.share));
    await tester.pump();
    final button = tester.getRect(find.ancestor(
        of: find.byIcon(Icons.share), matching: find.byType(IconButton)));
    expect(shared.single["subject"], "OPTIMISE Debug Information");
    expect(
        Rect.fromLTWH(
            (shared.single["originX"] as num).toDouble(),
            (shared.single["originY"] as num).toDouble(),
            (shared.single["originWidth"] as num).toDouble(),
            (shared.single["originHeight"] as num).toDouble()),
        button,
        reason: "an iPad anchors the share sheet there");
  });
}
