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
/// restart. [app], [warn] and [success] do not vary by brightness today;
/// [error], [appInk], [warnInk] and [text] do — [text] mirrors the Material
/// typography's own body color.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.app,
    required this.appInk,
    required this.warn,
    required this.warnInk,
    required this.error,
    required this.success,
    required this.text,
  });

  final Color app;
  final Color appInk;
  final Color warn;
  final Color warnInk;
  final Color error;
  final Color success;
  final Color text;

  @override
  AppColors copyWith(
      {Color? app,
      Color? appInk,
      Color? warn,
      Color? warnInk,
      Color? error,
      Color? success,
      Color? text}) {
    return AppColors(
      app: app ?? this.app,
      appInk: appInk ?? this.appInk,
      warn: warn ?? this.warn,
      warnInk: warnInk ?? this.warnInk,
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
  // For text and thin marks: the fill reads 2.4:1 on white, the ink 5:1.
  // On dark surfaces the fill is its own ink.
  static const Color appInkColorLight = Color(0xFF007c7c);
  static const Color appInkColorDark = appColor;
  static const Color warnColor = Color(0xFFec835a);
  // The fill reads 2.6:1 on white, too low for a standalone icon; the ink
  // reads 5:1. On dark surfaces the fill is already its own ink.
  static const Color warnInkColorLight = Color(0xFFb85026);
  static const Color warnInkColorDark = warnColor;
  static const Color errorColorLight = Color(0xFFe7000b);
  static const Color errorColorDark = Color(0xFFff6467);
  static const Color successColor = Color(0xFF0ca30d);

  // Hand-written so surfaces stay achromatic; fromSeed tints every role.
  // primary is the ink because Material defaults paint it as text; the brand
  // fill with content on top is primaryContainer.
  static const ColorScheme _lightColorScheme = ColorScheme(
    brightness: Brightness.light,
    primary: appInkColorLight,
    onPrimary: Colors.white,
    primaryContainer: appColor,
    onPrimaryContainer: Colors.black,
    secondary: Color(0xFF737373),
    onSecondary: Colors.white,
    error: errorColorLight,
    onError: Colors.white,
    surface: Colors.white,
    onSurface: Color(0xFF0a0a0a),
    onSurfaceVariant: Color(0xFF737373),
    // outline is the component-boundary role (switch off-state,
    // OutlinedButton, input borders) and must clear 3:1; outlineVariant is
    // for a merely decorative line (card border, divider) and stays faint.
    outline: Color(0xFF8a8a8a),
    outlineVariant: Color(0xFFe5e5e5),
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Colors.white,
    surfaceContainer: Color(0xFFf5f5f5),
    surfaceContainerHigh: Color(0xFFf5f5f5),
    surfaceContainerHighest: Color(0xFFf5f5f5),
    surfaceTint: Colors.transparent,
  );

  static const ColorScheme _darkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: appColor,
    onPrimary: Colors.black,
    primaryContainer: appColor,
    onPrimaryContainer: Colors.black,
    secondary: Color(0xFFa1a1a1),
    onSecondary: Color(0xFF0a0a0a),
    error: errorColorDark,
    onError: Colors.black,
    surface: Color(0xFF0a0a0a),
    onSurface: Color(0xFFfafafa),
    onSurfaceVariant: Color(0xFFa1a1a1),
    outline: Color(0xFF7a7a7a),
    outlineVariant: Color.fromRGBO(255, 255, 255, 0.10),
    surfaceContainerLowest: Color(0xFF171717),
    surfaceContainerLow: Color(0xFF171717),
    surfaceContainer: Color(0xFF262626),
    surfaceContainerHigh: Color(0xFF262626),
    surfaceContainerHighest: Color(0xFF262626),
    surfaceTint: Colors.transparent,
  );

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
      colorScheme: _lightColorScheme,
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          padding: WidgetStateProperty.all(MyTheme.inset),
          foregroundColor: WidgetStateProperty.all(MyTheme.appInkColorLight),
        ),
      ),
      appBarTheme: AppBarTheme(
          backgroundColor: _lightColorScheme.surface,
          foregroundColor: _lightColorScheme.onSurface,
          scrolledUnderElevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        shadowColor: Colors.black,
          height: 60,
          backgroundColor: _lightColorScheme.surface,
          surfaceTintColor: Colors.transparent,
          // The M3 default indicator is secondaryContainer, grey here.
          indicatorColor: _lightColorScheme.primary,
          iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? _lightColorScheme.onPrimary
                  : _lightColorScheme.onSurfaceVariant)),
      ),
      scaffoldBackgroundColor: Colors.white,
      elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
              backgroundColor: MyTheme.appColor,
              foregroundColor: Colors.black,
          )
      ),
      // FilledButton defaults to primary, the ink; it wants the brand fill.
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              backgroundColor: MyTheme.appColor,
              foregroundColor: Colors.black,
          )
      ),
      cardTheme:  CardThemeData(
        shape: BeveledRectangleBorder(
            borderRadius: BorderRadius.circular(0),
            // outlineVariant, not outline: a card border is decorative and
            // stays faint, unlike a component boundary.
            side: BorderSide(color: _lightColorScheme.outlineVariant, width: 1))),
      // The M3 default inactive track (surfaceContainerHighest) is ~1.1:1 on
      // white; outline is the nearest role that is actually a boundary.
      sliderTheme: SliderThemeData(inactiveTrackColor: _lightColorScheme.outline),
      // Dialogs on the card surface, not the muted one, so controls drawn on
      // the muted tone (switch track, chips) stay distinguishable inside them.
      dialogTheme: DialogThemeData(backgroundColor: _lightColorScheme.surfaceContainerLow),
    );
    return theme.copyWith(extensions: [
      AppColors(
        app: appColor,
        appInk: appInkColorLight,
        warn: warnColor,
        warnInk: warnInkColorLight,
        error: errorColorLight,
        success: successColor,
        text: theme.textTheme.bodyMedium!.color!,
      ),
    ]);
  }

  static final ThemeData materialDarkTheme = _buildMaterialDarkTheme();

  static ThemeData _buildMaterialDarkTheme() {
    final theme = ThemeData(
    platform: TargetPlatform.android,
    colorScheme: _darkColorScheme,
    useMaterial3: true,
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        padding: WidgetStateProperty.all(MyTheme.inset),
        foregroundColor: WidgetStateProperty.all(MyTheme.appInkColorDark),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: _darkColorScheme.surface,
      foregroundColor: _darkColorScheme.onSurface,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _darkColorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        indicatorColor: _darkColorScheme.primary,
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? _darkColorScheme.onPrimary
                : _darkColorScheme.onSurfaceVariant)),
      height: 60
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: MyTheme.appColor,
          foregroundColor: Colors.black,
        )
    ),
    filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: MyTheme.appColor,
          foregroundColor: Colors.black,
        )
    ),
      cardTheme:  CardThemeData(
          shape: BeveledRectangleBorder(
              borderRadius: BorderRadius.circular(0),
          )
      ),
      sliderTheme: SliderThemeData(inactiveTrackColor: _darkColorScheme.outline),
      dialogTheme: DialogThemeData(backgroundColor: _darkColorScheme.surfaceContainerLow),
    );
    return theme.copyWith(extensions: [
      AppColors(
        app: appColor,
        appInk: appInkColorDark,
        warn: warnColor,
        warnInk: warnInkColorDark,
        error: errorColorDark,
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
