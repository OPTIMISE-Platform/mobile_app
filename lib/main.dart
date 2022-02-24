import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/device_list.dart';

Future main() async {
  await dotenv.load(fileName: ".env");
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  _MyAppState() {
    Auth.login();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: MyTheme.materialTheme,
      child: PlatformProvider(
        settings: PlatformSettingsData(iosUsesMaterialWidgets: true),
        builder: (context) => PlatformApp(
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            DefaultMaterialLocalizations.delegate,
            DefaultWidgetsLocalizations.delegate,
            DefaultCupertinoLocalizations.delegate,
          ],
          home: DeviceList(),
          material: (_, __) => MaterialAppData(
            theme: MyTheme.materialTheme,
          ),
          cupertino: (_, __) => MyTheme.cupertinoAppData,
        ),
      ),
    );
  }
}
