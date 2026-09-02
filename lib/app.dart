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
import 'package:mobile_app/restart_controller.dart';
import 'package:mobile_app/services/app_update.dart';
import 'package:mobile_app/theme.dart';

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  // A new [UniqueKey] forces the entire subtree to rebuild, effectively
  // restarting the app without relaunching the process.
  Key _appKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppUpdater.cleanup();
    RestartController.instance.addListener(_onRestartRequested);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RestartController.instance.removeListener(_onRestartRequested);
    super.dispose();
  }

  void _onRestartRequested() {
    debugPrint('RESTART REQUESTED');
    setState(() => _appKey = UniqueKey());
  }

  @override
  void didChangePlatformBrightness() {
    // MaterialApp follows the OS on its own; MyTheme's colour snapshot does
    // not, and the widgets that paint with MyTheme.textColor would keep the
    // old brightness until a restart.
    if (MyTheme.followSystemBrightness()) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('MyApp rebuild');
    return MaterialApp(
      key: _appKey,
      navigatorKey: navigatorKey,
      theme: MyTheme.materialTheme,
      darkTheme: MyTheme.materialDarkTheme,
      themeMode: MyTheme.themeMode,
      home: const Home(),
    );
  }
}