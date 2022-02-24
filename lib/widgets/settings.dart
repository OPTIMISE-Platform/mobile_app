import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:mobile_app/widgets/app_bar.dart';

import '../services/auth.dart';
import '../theme.dart';

class Settings extends StatefulWidget {
  Settings({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  late final MyAppBar _appBar;

  _SettingsState() {
    _appBar = MyAppBar();
    _appBar.setTitle("Settings");
  }

  @override
  Widget build(BuildContext context) {
    return PlatformScaffold(
        appBar: _appBar.getAppBar(context, []),
        body: ListView(
          children: [
            ListTile(
              title: Text("Switch Style"),
              onTap: () => MyTheme.toggleTheme(context),
            ),
            Divider(),
            ListTile(
              title: Text("Logout"),
              onTap: () => Auth.logout(),
            ),
            // const Divider(),
          ],
        ),
    );
  }
}

