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
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/widgets/app_bar.dart';
import 'package:mobile_app/widgets/page_spinner.dart';
import 'package:mobile_app/widgets/toast.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
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
          Consumer<AppState>(
            builder: (context, state, child) => ListTile(
              title: const Text("Logout"),
              onTap: () {
                Navigator.push(
                    context,
                    platformPageRoute(
                      context: context,
                      builder: (context) => const PageSpinner("Logout"),
                    ));
                Auth.logout(context, state);
              },
            ),
          ),
        ],
      ),
    );
  }
}
