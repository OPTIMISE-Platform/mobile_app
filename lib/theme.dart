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

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:intl/intl.dart';

typedef ThemeStyle = String;

const ThemeStyle themeMaterial = "material";
const ThemeStyle themeCupertino = "cupertino";

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

  static ThemeData materialTheme = ThemeData(
      cupertinoOverrideTheme: cupertinoTheme,
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
      floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: MyTheme.appColor));

  static ThemeData materialDarkTheme = ThemeData(
    cupertinoOverrideTheme: cupertinoTheme,
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
    brightness: Brightness.dark,
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        padding: MaterialStateProperty.all(MyTheme.inset),
        foregroundColor: MaterialStateProperty.all(const Color(0xFF32b8ba)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(backgroundColor: MyTheme.appColor),
  );

  static CupertinoThemeData cupertinoTheme = const CupertinoThemeData(
    primaryColor: Color(0xFF32b8ba),
    brightness: Brightness.light,
  );

  static CupertinoAppData cupertinoAppData = CupertinoAppData(theme: cupertinoTheme);

  static TextStyle? get textStyle {
    if (isDarkMode) {
      return currentTheme == themeMaterial ? materialDarkTheme.textTheme.bodyMedium : cupertinoTheme.textTheme.textStyle;
    }
    return currentTheme == themeMaterial ? materialTheme.textTheme.bodyMedium : cupertinoTheme.textTheme.textStyle;
  }

  static Color? get textColor {
    return textStyle?.color;
  }

  static bool get isDarkMode {
    return currentColor == dark;
  }

  static TargetPlatform initialPlatform = kIsWeb
      ? TargetPlatform.android
      : Platform.isIOS
          ? TargetPlatform.iOS
          : TargetPlatform.android;
  static ThemeStyle currentTheme = kIsWeb
      ? themeMaterial
      : Platform.isIOS
          ? themeCupertino
          : themeMaterial;
  static ThemeStyle currentColor = SchedulerBinding.instance.window.platformBrightness == Brightness.dark ? dark : light;

  static loadTheme() async {
    var val = Settings.getTheme();
    if (val == themeMaterial) {
      initialPlatform = TargetPlatform.android;
      currentTheme = themeMaterial;
    } else if (val == themeCupertino) {
      initialPlatform = TargetPlatform.iOS;
      currentTheme = themeCupertino;
    }

    val = Settings.getThemeColor();
    if (val == dark) {
      currentColor = dark;
    } else if (val == light) {
      currentColor = light;
    }
  }

  static toggleTheme(BuildContext context) async {
    final p = PlatformProvider.of(context);
    if (p == null) {
      return;
    }
    isMaterial(context) ? await selectTheme(context, themeCupertino) : await selectTheme(context, themeMaterial);
  }

  static selectTheme(BuildContext context, ThemeStyle? theme) async {
    final p = PlatformProvider.of(context);
    switch (theme) {
      case themeMaterial:
        await Settings.setTheme(theme!);
        currentTheme = themeMaterial;
        p?.changeToMaterialPlatform();
        break;
      case themeCupertino:
        await Settings.setTheme(theme!);
        currentTheme = themeCupertino;
        p?.changeToCupertinoPlatform();
        break;
      default:
        await Settings.resetTheme();
        currentTheme = Platform.isIOS ? themeCupertino : themeMaterial;
        p?.changeToAutoDetectPlatform();
    }
  }

  static selectThemeColor(ThemeColor? theme) async {
    switch (theme) {
      case dark:
      case light:
        await Settings.setThemeColor(theme!);
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
}
