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

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:intl/intl.dart';
import "package:intl/intl_standalone.dart"
if (dart.library.html) "package:intl/intl_browser.dart";
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/services/app_update.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/theme.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'home.dart';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await AppState.queueRemoteMessage(message);
}

Future main() async {
  await dotenv.load(fileName: ".env");
  await MyTheme.loadTheme();
  await Auth.init();
  await findSystemLocale();
  await initializeDateFormatting(Intl.systemLocale, null);
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(
    RootRestorationScope(restorationId: "root", child:
      ChangeNotifierProvider(
        create: (context) => AppState(),
        child: const MyApp(),
      ))
  );
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  _MyAppState();

  @override
  Widget build(BuildContext context) {
    AppUpdater.cleanup();
    return Theme(
      data: MyTheme.materialTheme,
      child: PlatformProvider(
        initialPlatform: MyTheme.initialPlatform,
        settings: PlatformSettingsData(iosUsesMaterialWidgets: true),
        builder: (context) => PlatformApp(
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            DefaultMaterialLocalizations.delegate,
            DefaultWidgetsLocalizations.delegate,
            DefaultCupertinoLocalizations.delegate,
          ],
          home: const Home(),
          material: (_, __) => MaterialAppData(
            theme: MyTheme.materialTheme,
            darkTheme: MyTheme.materialDarkTheme,
          ),
          cupertino: (_, __) => MyTheme.cupertinoAppData,
        ),
      ),
    );
  }
}
