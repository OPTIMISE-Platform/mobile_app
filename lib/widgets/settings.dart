import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/widgets/app_bar.dart';
import 'package:mobile_app/widgets/page_spinner.dart';
import 'package:mobile_app/widgets/toast.dart';


import '../services/auth.dart';
import '../theme.dart';

class Settings extends StatefulWidget {
  const Settings({Key? key}) : super(key: key);

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
      appBar: _appBar.getAppBar(context),
      body: ListView(
        children: [
          ListTile(
            title: const Text("Switch Style"),
            onTap: () => MyTheme.toggleTheme(context),
          ),
          const Divider(),
          ListTile(
            title: const Text("Clear Cache"),
            onTap: () {
              CacheHelper.clearCache();
              Toast.showConfirmationToast(context, "Cache cleared");
            },
          ),
          const Divider(),
          ListTile(
            title: const Text("Logout"),
            onTap: () {
              Navigator.push(
                  context,
                  platformPageRoute(
                    context: context,
                    builder: (context) => const PageSpinner("Logout"),
                  ));
              Auth.logout(context);
            },
          ),
          // const Divider(),
        ],
      ),
    );
  }
}
