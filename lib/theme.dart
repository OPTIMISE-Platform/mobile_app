/*
 * Copyright 2022 InfAI (CC SES)
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
import 'package:flutter/scheduler.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:intl/intl.dart';
import 'package:mobile_app/services/settings.dart';

typedef ThemeStyle = String;

const ThemeStyle themeMaterial = "material";

typedef ThemeColor = String;

const ThemeColor dark = "dark";
const ThemeColor light = "light";

class MyTheme {
  static const Color appColor = Color.fromRGBO(50, 184, 186, 1);
  static const Color warnColor = Colors.deepOrange;
  static const Color errorColor = Colors.redAccent;
  static const Color successColor = Colors.greenAccent;

  static const double insetSize = 12.0;
  static const EdgeInsets inset = EdgeInsets.all(insetSize);

  static final formatSS = DateFormat.s();
  static final formatMM = DateFormat.m();
  static final formatMMSS = DateFormat.ms();
  static final formatHH = DateFormat.H();
  static final formatHHMM = DateFormat.Hm();
  static final formatE = DateFormat.E();
  static final formatEHH = DateFormat.E().add_H();
  static final formatEHHMM = DateFormat.E().add_Hm();
  static final formatMMM = DateFormat.MMM();
  static final formatDDMM = DateFormat('dd.MM');
  static final formatY = DateFormat.y();
  static final formatEddMMy = DateFormat('E, dd.MM.y');

  static ThemeData materialTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF32b8ba)),
      primarySwatch: const MaterialColor(0xFF32b8ba, <int, Color>{
        50: Color.fromRGBO(50, 184, 186, 0.1),
        100: Color.fromRGBO(50, 184, 186, 0.2),
        200: Color.fromRGBO(50, 184, 186, 0.3),
        300: Color.fromRGBO(50, 184, 186, 0.4),
        400: Color.fromRGBO(50, 184, 186, 0.5),
        500: Color.fromRGBO(50, 184, 186, 0.6),
        600: Color.fromRGBO(50, 184, 186, 0.7),
        700: Color.fromRGBO(50, 184, 186, 0.8),
        800: Color.fromRGBO(50, 184, 186, 0.9),
        900: Color.fromRGBO(50, 184, 186, 1),
      }),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          padding: MaterialStateProperty.all(MyTheme.inset),
          foregroundColor: MaterialStateProperty.all(const Color(0xFF32b8ba)),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: MyTheme.appColor
      ),
      appBarTheme: const AppBarTheme(
          backgroundColor: MyTheme.appColor,
          foregroundColor: Colors.black,
          scrolledUnderElevation: 0,
      ),
      navigationBarTheme:  const NavigationBarThemeData(
        shadowColor: Colors.black,
          height: 60,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          indicatorColor: Colors.white,
      ),
      scaffoldBackgroundColor: Colors.white,
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
              backgroundColor: MyTheme.appColor,
              foregroundColor: Colors.black,
          )
      ),
      cardTheme:  CardTheme(
        shape: BeveledRectangleBorder(
            borderRadius: BorderRadius.circular(0),
            side: const BorderSide(color: Colors.white24, width: 1)))
  );

  static ThemeData materialDarkTheme = ThemeData(
    primaryColor: const Color(0xFF32b8ba),
    colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF32b8ba),
        brightness: Brightness.dark,
        secondary: const Color(0xFF33cca0),
      background: const Color(0xFF303030),
    ),
    useMaterial3: true,
    primarySwatch: const MaterialColor(0xFF32b8ba, <int, Color>{
      50: Color.fromRGBO(50, 184, 186, 0.1),
      100: Color.fromRGBO(50, 184, 186, 0.2),
      200: Color.fromRGBO(50, 184, 186, 0.3),
      300: Color.fromRGBO(50, 184, 186, 0.4),
      400: Color.fromRGBO(50, 184, 186, 0.5),
      500: Color.fromRGBO(50, 184, 186, 0.6),
      600: Color.fromRGBO(50, 184, 186, 0.7),
      700: Color.fromRGBO(50, 184, 186, 0.8),
      800: Color.fromRGBO(50, 184, 186, 0.9),
      900: Color.fromRGBO(50, 184, 186, 1),
    }),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        padding: MaterialStateProperty.all(MyTheme.inset),
        foregroundColor: MaterialStateProperty.all(const Color(0xFF32b8ba)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: MyTheme.appColor
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF424242),
      foregroundColor: Colors.white,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme:  const NavigationBarThemeData(
        backgroundColor: Color(0xFF424242),
        surfaceTintColor: Color(0xFF424242),
        indicatorColor: Color(0xFF424242),
      height: 60
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: MyTheme.appColor,
          foregroundColor: Colors.black,
        )
    ),
      cardTheme:  CardTheme(
          shape: BeveledRectangleBorder(
              borderRadius: BorderRadius.circular(0),
          )
      )
  );

  static TextStyle? get textStyle {
    if (isDarkMode) {
      return materialDarkTheme.textTheme.bodyMedium;
    }
    return materialTheme.textTheme.bodyMedium;
  }

  static Color? get textColor {
    return textStyle?.color;
  }

  static bool get isDarkMode {
    return currentColor == dark;
  }

  static TargetPlatform initialPlatform = TargetPlatform.android;

  static ThemeStyle currentTheme = themeMaterial;

  static ThemeStyle currentColor = SchedulerBinding.instance.window.platformBrightness == Brightness.dark ? dark : light;

  static ThemeMode? themeMode = ThemeMode.light;

  static loadTheme() async {
    var val = Settings.getTheme();

    val = Settings.getThemeColor();
    if (val == dark) {
      themeMode = ThemeMode.dark;
      currentColor = dark;
    } else if (val == light) {
      themeMode = ThemeMode.light;
      currentColor = light;
    }
  }

  static selectThemeColor(ThemeColor? theme) async {
    switch (theme) {
      case dark:
        await Settings.setThemeColor(theme!);
        currentColor = theme;
        themeMode = ThemeMode.dark;
      case light:
        await Settings.setThemeColor(theme!);
        themeMode = ThemeMode.light;
        currentColor = theme;
        break;
      default:
        await Settings.resetThemeColor();
        currentColor = SchedulerBinding.instance.window.platformBrightness == Brightness.dark ? dark : light;
    }
  }

  static bool get canChangeColorTheme {
    return currentTheme == themeMaterial;
  }

  /// Retrieve a nice color. Colors are rotated based on i
  static Color getSomeColor(int i) {
    const List<Color> colors = [
      MyTheme.appColor,
      Colors.indigo,
      Colors.redAccent,
      Colors.blueAccent,
      Colors.teal,
      Colors.deepOrangeAccent,
      Colors.blueGrey
    ];
    return colors[i % colors.length];
  }
}
