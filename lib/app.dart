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
import 'package:mobile_app/home.dart';
import 'package:mobile_app/navigator_key.dart';
import 'package:mobile_app/services/app_update.dart';
import 'package:mobile_app/theme.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    AppUpdater.cleanup();
  }

  @override
  Widget build(BuildContext context) {
    // MaterialApp resolves ThemeMode.system, and reacts to the OS brightness
    // changing, on its own - no restart or re-key needed for either that or a
    // user-picked mode, since every colour read now comes from Theme.of(context).
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: MyTheme.themeModeNotifier,
      builder: (context, themeMode, child) => MaterialApp(
        navigatorKey: navigatorKey,
        theme: MyTheme.materialTheme,
        darkTheme: MyTheme.materialDarkTheme,
        themeMode: themeMode,
        home: child,
      ),
      child: const Home(),
    );
  }
}