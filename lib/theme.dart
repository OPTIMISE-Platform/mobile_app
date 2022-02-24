import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

typedef ThemeStyle = String;

class MyTheme {
  static Color appColor = const Color.fromRGBO(50, 184, 186, 1);

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
        padding: MaterialStateProperty.all(const EdgeInsets.all(16.0)),
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
