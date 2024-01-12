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
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import "package:intl/intl_standalone.dart" if (dart.library.html) "package:intl/intl_browser.dart";
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/services/app_update.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/shared/location.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/toast.dart';
import 'package:open_location_picker/open_location_picker.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:mobile_app/firebase_options.dart';

import 'package:mobile_app/home.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await AppState.queueRemoteMessage(message);
}

Future main() async {
  final start = DateTime.now();
  await dotenv.load(fileName: ".env");
  print("dotenv init took ${DateTime.now().difference(start)}");

  var sub = DateTime.now();
  await Settings.init();
  print("Settings init took ${DateTime.now().difference(sub)}");

  sub = DateTime.now();
  await MyTheme.loadTheme();
  print("MyTheme init took ${DateTime.now().difference(sub)}");

  sub = DateTime.now();
  await findSystemLocale();
  print("findSystemLocale init took ${DateTime.now().difference(sub)}");

  sub = DateTime.now();
  await initializeDateFormatting(Intl.systemLocale, null);
  print("initializeDateFormatting init took ${DateTime.now().difference(sub)}");

  sub = DateTime.now();
  WidgetsFlutterBinding.ensureInitialized();
  print("WidgetsFlutterBinding init took ${DateTime.now().difference(sub)}");

  sub = DateTime.now();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  print("Firebase init took ${DateTime.now().difference(sub)}");

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  sub = DateTime.now();
  await Auth().init();
  print("Auth init took ${DateTime.now().difference(sub)}");

  sub = DateTime.now();
  await CacheHelper.scheduleCacheUpdates().catchError((_) => Toast.showToastNoContext("Could not refresh cache"));
  print("Cache init took ${DateTime.now().difference(sub)}");

  print("App init took ${DateTime.now().difference(start)}");
  runApp(RootRestorationScope(
      restorationId: "root",
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (context) => AppState(),
          ),
          ChangeNotifierProvider(
            create: (context) => Auth(),
          ),
        ],
        child: const MyApp(),
      )));
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  Key key = UniqueKey();

  MyAppState();

  void restartApp() {
    setState(() {
      key = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    AppUpdater.cleanup();
    return OpenMapSettings(
        onError: (context, error) {
          print(error.toString());
        },
        getCurrentLocation: () async {
          final pos = await determinePosition();
          if (pos == null) return null;
          return LatLng(pos.latitude, pos.longitude);
        },
        getLocationStream: () => Geolocator.getPositionStream().map((event) => LatLng(event.latitude, event.longitude)),
        child: Theme(
          key: key,
          data: MyTheme.materialTheme,
          child: PlatformProvider(
            initialPlatform: MyTheme.initialPlatform,
            settings: PlatformSettingsData(iosUsesMaterialWidgets: true),
            builder: (context) => PlatformApp(
              navigatorKey: navigatorKey,
              localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
                DefaultMaterialLocalizations.delegate,
                DefaultWidgetsLocalizations.delegate,
                DefaultCupertinoLocalizations.delegate,
              ],
              home: const Home(),
              material: (_, __) => MaterialAppData(
                title: "OPTIMISE",
                theme: MyTheme.isDarkMode ? MyTheme.materialDarkTheme : MyTheme.materialTheme,
              ),
              cupertino: (_, __) => MyTheme.cupertinoAppData,
            ),
          ),
        ));
  }
}
