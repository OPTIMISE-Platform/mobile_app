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
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:provider/provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Timeline logging writes an event per HTTP request; only useful while
  // profiling, so keep it out of release builds.
  if (kDebugMode) HttpClient.enableTimelineLogging = true;
  // Everything that escapes a catch is recorded here. Without it those
  // failures reach the console only, and the diagnostics dump a user shares
  // when something is wrong holds no trace of them. Neither handler shows
  // anything: a framework error can repeat per frame and would bury the
  // message that belongs to whatever the user just did.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    ErrorReporter.log("Unhandled framework error", details.exception,
        details.stack);
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    ErrorReporter.log("Unhandled error", error, stack);
    // Not claimed as handled - the platform still prints it as before.
    return false;
  };
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
        // create:, not .value — the lazy construction keeps AppState's setup
        // (mDNS discovery, the native pipe) off this build, which runs before
        // AppInitializer.runDeferred() is done.
        // It used to be load-bearing for more than timing: the constructor read
        // FirebaseMessaging.instance, which throws "No Firebase App '[DEFAULT]'
        // has been created" until runDeferred() initialized Firebase, and since
        // that future is not awaited a descendant could still get there first.
        // NotificationMixin resolves messaging on use now, so that race is gone.
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