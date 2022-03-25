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

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

typedef ThemeStyle = String;

class MyTheme {
  static const Color appColor = Color.fromRGBO(50, 184, 186, 1);
  static const Color warnColor = Colors.deepOrange;
  static const Color errorColor = Colors.redAccent;
  static const Color successColor = Colors.greenAccent;

  static const double insetSize = 12.0;
  static const EdgeInsets inset = EdgeInsets.all(insetSize);

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
    
  );

  static CupertinoThemeData cupertinoTheme =  const CupertinoThemeData(
      primaryColor: Color(0xFF32b8ba),
      primaryContrastingColor: Colors.white,
      barBackgroundColor: Colors.black,
      scaffoldBackgroundColor: Colors.white);

  static CupertinoAppData cupertinoAppData = CupertinoAppData(
      theme: cupertinoTheme);

  static const _storage = FlutterSecureStorage();
  static const _storageKeyTheme =  "theme";
  static const ThemeStyle themeMaterial =  "material";
  static const ThemeStyle themeCupertino =  "cupertino";

  static loadTheme(BuildContext context) async {
    await selectTheme(context, await _storage.read(key: _storageKeyTheme));
  }

  static toggleTheme(BuildContext context) async {
    final p = PlatformProvider.of(context);
    if (p == null) {
      return;
    }
    isMaterial(context)
        ? await selectTheme(context, themeCupertino)
        : await selectTheme(context, themeMaterial);
  }

  static selectTheme(BuildContext context, ThemeStyle? theme) async {
    final p = PlatformProvider.of(context);
    switch (theme) {
      case themeMaterial:
        p?.changeToMaterialPlatform();
        await _storage.write(key: _storageKeyTheme, value: theme);
        break;
      case themeCupertino:
        p?.changeToCupertinoPlatform();
        await _storage.write(key: _storageKeyTheme, value: theme);
        break;
      default:
        p?.changeToAutoDetectPlatform();
        await _storage.delete(key: _storageKeyTheme);
    }
  }
}
