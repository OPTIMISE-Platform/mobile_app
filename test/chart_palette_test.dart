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

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/theme.dart';

/// WCAG 2.x contrast ratio between two opaque colours.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  // The light and dark scaffold and card surfaces the charts sit on.
  const surfaces = {
    "white": Color(0xFFffffff),
    "light grey": Color(0xFFf5f5f5),
    "near black": Color(0xFF0a0a0a),
    "dark grey": Color(0xFF171717),
  };

  group("chart palette", () {
    test("contrast helper matches the WCAG extremes", () {
      expect(contrast(const Color(0xFF000000), const Color(0xFFffffff)),
          closeTo(21, 1e-9));
      expect(contrast(const Color(0xFFffffff), const Color(0xFFffffff)), 1);
    });

    test("every colour holds 3:1 on every surface", () {
      for (var i = 0; i < 6; i++) {
        final color = MyTheme.getSomeColor(i);
        for (final surface in surfaces.entries) {
          expect(contrast(color, surface.value), greaterThanOrEqualTo(3.0),
              reason: "series $i on ${surface.key}");
        }
      }
    });

    test("readableOn picks the text colour with the higher contrast", () {
      const dark = Color(0xFF000000);
      const light = Color(0xFFffffff);
      expect(MyTheme.readableOn(const Color(0xFFffff00), dark, light), dark);
      expect(MyTheme.readableOn(const Color(0xFF000080), dark, light), light);
      // Argument order does not matter, a tie takes the first.
      expect(MyTheme.readableOn(const Color(0xFFffff00), light, dark), dark);
      expect(MyTheme.readableOn(const Color(0xFF808080), dark, dark), dark);
    });

    test("black or white labels reach 4.5:1 on every series colour", () {
      for (var i = 0; i < 6; i++) {
        final bg = MyTheme.getSomeColor(i);
        final text = MyTheme.readableOn(
            bg, const Color(0xFF000000), const Color(0xFFffffff));
        expect(contrast(text, bg), greaterThanOrEqualTo(4.5), reason: "series $i");
      }
    });

    test("has six distinct colours that then repeat", () {
      final colors = [for (var i = 0; i < 6; i++) MyTheme.getSomeColor(i)];
      expect(colors.toSet().length, 6);
      expect(MyTheme.getSomeColor(6), colors[0]);
      expect(MyTheme.getSomeColor(13), colors[1]);
    });
  });
}
