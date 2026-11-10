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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/config/functions/function_config.dart';
import 'package:mobile_app/config/functions/set_color.dart';
import 'package:mobile_app/models/characteristic.dart';
import 'package:mobile_app/models/content_variable.dart';

/// Controlling a group opens the input dialog with the value its devices
/// share, instead of their per-device list (SNRGY-3855), and the text field
/// opens focused with that value selected so typing replaces it.
void main() {
  // Characteristic.build looks up special configs keyed by dotenv ids.
  setUpAll(() async {
    if (!dotenv.isInitialized) {
      dotenv.loadFromString(envString: await File(".env.example").readAsString());
    }
  });

  Characteristic temperature(dynamic value) =>
      Characteristic("id", "Temperature", ContentVariable.float, null, null, value, null, "°C", null);

  group("commonValue", () {
    test("equal values merge into one", () {
      expect(commonValue([17, 17, 17]), 17);
    });

    test("int and double of the same number merge", () {
      expect(commonValue([17, 17.0]), 17);
    });

    test("differing values give none", () {
      expect(commonValue([17, 18, 17]), isNull);
    });

    test("devices without a reading are skipped", () {
      expect(commonValue([null, 17, null, 17]), 17);
      expect(commonValue([null, null]), isNull);
      expect(commonValue([]), isNull);
    });

    test("structures compare by their fields", () {
      expect(commonValue([
        {"r": 1, "g": 2, "b": 3},
        {"r": 1, "g": 2, "b": 3},
      ]), {"r": 1, "g": 2, "b": 3});
      expect(commonValue([
        {"r": 1, "g": 2, "b": 3},
        {"r": 1, "g": 2, "b": 4},
      ]), isNull);
    });
  });

  group("text field", () {
    Future<EditableText> pump(WidgetTester tester, Characteristic c, {required bool focusInput}) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Builder(builder: (context) => c.build(context, (fn) => fn(), focusInput: focusInput)))));
      await tester.pump();
      return tester.widget<EditableText>(find.byType(EditableText));
    }

    testWidgets("opens focused with the current value selected", (tester) async {
      final field = await pump(tester, temperature(17), focusInput: true);
      expect(field.focusNode.hasFocus, isTrue);
      expect(field.controller.text, "17");
      expect(field.controller.selection, const TextSelection(baseOffset: 0, extentOffset: 2));
      expect(tester.testTextInput.isVisible, isTrue);
    });

    testWidgets("opens empty and focused without a value", (tester) async {
      final field = await pump(tester, temperature(null), focusInput: true);
      expect(field.focusNode.hasFocus, isTrue);
      expect(field.controller.text, isEmpty);
    });

    testWidgets("stays unfocused outside the control dialog", (tester) async {
      final field = await pump(tester, temperature(17), focusInput: false);
      expect(field.focusNode.hasFocus, isFalse);
    });
  });

  // The special configs live across dialogs. A group whose devices differ
  // must not open with the input of the dialog before.
  testWidgets("a config kept across dialogs starts empty without a value", (tester) async {
    final config = FunctionConfigSetColor()..characteristic = temperature(null);
    late BuildContext context;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      context = c;
      return const SizedBox();
    })));
    config.build(context, (fn) => fn(), 17);
    expect(config.getConfiguredValue(), 17);
    config.build(context, (fn) => fn());
    expect(config.getConfiguredValue(), isNull);
  });
}
