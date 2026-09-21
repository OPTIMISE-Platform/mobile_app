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
import 'package:mobile_app/config/characteristics/rgb.dart';
import 'package:mobile_app/models/characteristic.dart';
import 'package:mobile_app/models/content_variable.dart';

/// The r/g/b the device receives must stay 0..255 ints. Color's own channels
/// are 0..1 doubles, so a channel read that skips the conversion sends 0/1.
void main() {
  Characteristic newCharacteristic() => Characteristic(
      "id", "color", ContentVariable.structure, null, null, null, null, "", null);

  Future<void> pumpPicker(WidgetTester tester, Characteristic c) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: Builder(builder: (context) => RGB.build(context, c, (fn) => fn()))))));
  }

  Future<void> tapQuickButton(WidgetTester tester, Color color) async {
    final swatch = find.byWidgetPredicate(
        (w) => w is Icon && w.icon == Icons.square && w.color == color);
    expect(swatch, findsOneWidget);
    await tester.tap(find.ancestor(of: swatch, matching: find.byType(IconButton)));
    await tester.pump();
  }

  testWidgets("white maps to 255, not 1", (tester) async {
    final c = newCharacteristic();
    await pumpPicker(tester, c);
    await tapQuickButton(tester, Colors.white);
    expect(c.value, <String, int>{"r": 255, "g": 255, "b": 255});
  });

  testWidgets("a mixed colour round-trips exactly", (tester) async {
    final c = newCharacteristic();
    await pumpPicker(tester, c);
    await tapQuickButton(tester, const Color.fromARGB(255, 253, 244, 220));
    expect(c.value, <String, int>{"r": 253, "g": 244, "b": 220});
  });

  test("every 0..255 channel survives the Color round-trip", () {
    for (var v = 0; v <= 255; v++) {
      final c = Color.fromARGB(255, v, v, v);
      expect((c.r * 255.0).round() & 0xff, v, reason: "channel $v");
    }
  });
}
