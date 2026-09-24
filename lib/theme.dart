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


import 'package:flutter/material.dart';
import 'package:mobile_app/services/settings.dart';

typedef ThemeStyle = String;

const ThemeStyle themeMaterial = "material";

typedef ThemeColor = String;

const ThemeColor dark = "dark";
const ThemeColor light = "light";

/// App-specific colours as a [ThemeExtension], so widgets read them off
/// [Theme.of(context)] instead of a static snapshot that only updates on
/// restart. [app]/[warn]/[error]/[success] do not vary by brightness today;
/// [text] does, and mirrors the Material typography's own body color.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.app,
    required this.warn,
    required this.error,
    required this.success,
    required this.text,
  });

  final Color app;
  final Color warn;
  final Color error;
  final Color success;
  final Color text;

  @override
  AppColors copyWith(
      {Color? app, Color? warn, Color? error, Color? success, Color? text}) {
    return AppColors(
      app: app ?? this.app,
      warn: warn ?? this.warn,
      error: error ?? this.error,
      success: success ?? this.success,
      text: text ?? this.text,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    // Snaps rather than blending the individual colours: these are discrete
    // theme choices, not an animation between them.
    return t < 0.5 ? this : other;
  }
}

/// Shorthand for `Theme.of(context).extension<AppColors>()!`.
extension AppColorsContext on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}

class MyTheme {
  static const Color appColor = Color.fromRGBO(50, 184, 186, 1);
  static const Color warnColor = Colors.deepOrange;
  static const Color errorColor = Colors.redAccent;
  static const Color successColor = Colors.greenAccent;

  static const double insetSize = 12.0;
  static const EdgeInsets inset = EdgeInsets.all(insetSize);

  // Pinned to Android on every platform: the adaptive widgets and dialogs then
  // stay Material on iOS, which is what the app has always shipped there. The
  // dialog contents are Material-only and would lack their ancestor otherwise.
  static final ThemeData materialTheme = _buildMaterialTheme();

  static ThemeData _buildMaterialTheme() {
    final theme = ThemeData(
      platform: TargetPlatform.android,
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
          padding: WidgetStateProperty.all(MyTheme.inset),
          foregroundColor: WidgetStateProperty.all(const Color(0xFF32b8ba)),
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
      navigationBarTheme:  NavigationBarThemeData(
        shadowColor: Colors.black,
          height: 60,
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          // Colors.white made the M3 selection indicator invisible here.
          indicatorColor: Colors.teal.shade50,
      ),
      scaffoldBackgroundColor: Colors.white,
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
              backgroundColor: MyTheme.appColor,
              foregroundColor: Colors.black,
          )
      ),
      cardTheme:  CardThemeData(
        shape: BeveledRectangleBorder(
            borderRadius: BorderRadius.circular(0),
            side: const BorderSide(color: Colors.white24, width: 1)))
    );
    return theme.copyWith(extensions: [
      AppColors(
        app: appColor,
        warn: warnColor,
        error: errorColor,
        success: successColor,
        text: theme.textTheme.bodyMedium!.color!,
      ),
    ]);
  }

  static final ThemeData materialDarkTheme = _buildMaterialDarkTheme();

  static ThemeData _buildMaterialDarkTheme() {
    final theme = ThemeData(
    platform: TargetPlatform.android,
    primaryColor: const Color(0xFF32b8ba),
    colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF32b8ba),
        brightness: Brightness.dark,
        secondary: const Color(0xFF33cca0),
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
        padding: WidgetStateProperty.all(MyTheme.inset),
        foregroundColor: WidgetStateProperty.all(const Color(0xFF32b8ba)),
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
        // Matched the background, making the M3 selection indicator invisible.
        indicatorColor: MyTheme.appColor,
      height: 60
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: MyTheme.appColor,
          foregroundColor: Colors.black,
        )
    ),
      cardTheme:  CardThemeData(
          shape: BeveledRectangleBorder(
              borderRadius: BorderRadius.circular(0),
          )
      )
    );
    return theme.copyWith(extensions: [
      AppColors(
        app: appColor,
        warn: warnColor,
        error: errorColor,
        success: successColor,
        text: theme.textTheme.bodyMedium!.color!,
      ),
    ]);
  }

  static ThemeStyle currentTheme = themeMaterial;

  // Follows the system unless the user picked a colour. Widgets read the
  // active mode through [MaterialApp.themeMode] and `Theme.of(context)`, not
  // through this notifier - it only carries the persisted selection so
  // [MyApp] can rebuild the app's themeMode without re-keying the tree.
  static final ValueNotifier<ThemeMode> themeModeNotifier =
      ValueNotifier(ThemeMode.system);

  static loadTheme() async {
    final val = Settings.getThemeColor();
    if (val == dark) {
      themeModeNotifier.value = ThemeMode.dark;
    } else if (val == light) {
      themeModeNotifier.value = ThemeMode.light;
    }
  }

  static selectThemeColor(ThemeColor? theme) async {
    switch (theme) {
      case dark:
        await Settings.setThemeColor(theme!);
        themeModeNotifier.value = ThemeMode.dark;
      case light:
        await Settings.setThemeColor(theme!);
        themeModeNotifier.value = ThemeMode.light;
        break;
      default:
        await Settings.resetThemeColor();
        themeModeNotifier.value = ThemeMode.system;
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
