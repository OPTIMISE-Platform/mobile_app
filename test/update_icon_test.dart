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
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/app_bar.dart';

void main() {
  testWidgets("the update icon takes the new text colour after a theme switch",
      (tester) async {
    final mode = ValueNotifier(ThemeMode.light);
    await tester.pumpWidget(ValueListenableBuilder<ThemeMode>(
      valueListenable: mode,
      builder: (_, m, _) => MaterialApp(
        theme: MyTheme.materialTheme,
        darkTheme: MyTheme.materialDarkTheme,
        themeMode: m,
        home: const Scaffold(body: UpdateIcon()),
      ),
    ));

    mode.value = ThemeMode.dark;
    await tester.pump();
    // Past the theme cross-fade, early in the pulse, where the text colour
    // still dominates the interpolation.
    await tester.pump(const Duration(milliseconds: 250));

    final dark = MyTheme.materialDarkTheme.extension<AppColors>()!;
    final light = MyTheme.materialTheme.extension<AppColors>()!;
    final shown = tester.widget<Icon>(find.byIcon(Icons.system_update_alt)).color!;
    double distance(Color a, Color b) =>
        (a.r - b.r).abs() + (a.g - b.g).abs() + (a.b - b.b).abs();
    expect(distance(shown, dark.text), lessThan(distance(shown, light.text)));
  });
}
