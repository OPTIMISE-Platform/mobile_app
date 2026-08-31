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

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_app/app.dart';
import 'package:mobile_app/app_initializer.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Timeline logging writes an event per HTTP request; only useful while
  // profiling, so keep it out of release builds.
  if (kDebugMode) HttpClient.enableTimelineLogging = true;
  runApp(
    const _Bootstrap(),
  );
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await AppInitializer.run();

    if (!mounted) return;

    setState(() {
      _ready = true;
    });

    unawaited(AppInitializer.runDeferred());
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return MultiProvider(
      providers: [
        // create:, not .value — the lazy construction is load-bearing.
        // AppState's constructor reads FirebaseMessaging.instance, starts mDNS
        // discovery and initializes the native pipe, none of which exist until
        // AppInitializer.runDeferred() has run, and that runs after this build.
        // create: defers construction to the first read by a descendant, by
        // which time the setup is done; .value constructs it here and throws
        // "No Firebase App '[DEFAULT]' has been created", leaving a grey screen.
        //
        // The cost is that the provider owns these singletons and would dispose
        // them if it were ever removed from the tree. It never is: _Bootstrap
        // does not remount and RestartController re-keys only the Theme below.
        ChangeNotifierProvider(create: (_) => AppState()),
        ChangeNotifierProvider(create: (_) => Auth()),
      ],
      child: const MyApp(),
    );
  }
}