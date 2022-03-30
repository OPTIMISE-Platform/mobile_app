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
import 'package:mobile_app/services/app_update.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/widgets/app_bar.dart';
import 'package:mobile_app/widgets/page_spinner.dart';
import 'package:mobile_app/widgets/toast.dart';
import 'package:open_file/open_file.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../exceptions/no_network_exception.dart';
import '../services/auth.dart';
import '../theme.dart';

class Settings extends StatelessWidget {
  const Settings({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const appBar = MyAppBar("Settings");
    final appUpdater = AppUpdater();
    final List<Widget> children = [
      ListTile(
        title: const Text("Switch Style"),
        onTap: () => MyTheme.toggleTheme(context),
      ),
      const Divider(),
      ListTile(
        title: const Text("Clear Cache"),
        onTap: () {
          CacheHelper.clearCache();
          Toast.showConfirmationToast(context, "Cache cleared, please restart App");
        },
      ),
      const Divider(),
      Consumer<AppState>(
        builder: (context, state, child) => ListTile(
          title: const Text("Logout"),
          onTap: () async {
            Navigator.push(
                context,
                platformPageRoute(
                  context: context,
                  builder: (context) => const PageSpinner("Logout"),
                ));
            try {
              await Auth.logout(context, state);
            } catch (e) {
              Toast.showErrorToast(context, "Can't logout");
            }
          },
        ),
      ),
    ];

    if (appUpdater.updateSupported) {
      children.addAll([
        const Divider(),
        ListTile(
          title: const Text("Check Updates"),
          onTap: () async {
            late final bool updateAvailable;
            try {
              updateAvailable = await appUpdater.updateAvailable();
            } on NoNetworkException {
              Toast.showWarningToast(context, "Currently offline");
              return;
            } catch (e) {
              Toast.showErrorToast(context, "Error checking for updates");
              return;
            }
            if (!updateAvailable) {
              Toast.showConfirmationToast(context, "Already up to date!");
              return;
            } else {
              final proceed = await showPlatformDialog(
                  context: context,
                  builder: (context) => PlatformAlertDialog(
                        title: const Text("Update now?"),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Current Build: " + appUpdater.currentBuild.toString()),
                            Text("Latest Build: " + appUpdater.latestBuild.toString()),
                            Text("Download size: " + (appUpdater.downloadSize / 1000000.0).toStringAsFixed(1) + " MB"),
                          ],
                        ),
                        actions: [
                          PlatformDialogAction(
                            child: PlatformText('Cancel'),
                            onPressed: () => Navigator.pop(context, false),
                          ),
                          PlatformDialogAction(child: PlatformText('OK'), onPressed: () => Navigator.pop(context, true))
                        ],
                      ));
              if (proceed != true) {
                return;
              }
              final stream = appUpdater.downloadUpdate().asBroadcastStream();
              stream.listen(null, onDone: () => Navigator.pop(context));
              await showPlatformDialog(
                  context: context,
                  builder: (context) => PlatformAlertDialog(
                        title: const Text("Downloading Update..."),
                        content: StreamBuilder<double>(
                            stream: stream,
                            initialData: 0,
                            builder: (context, snapshot) {
                              return Column(mainAxisSize: MainAxisSize.min, children: [
                                LinearProgressIndicator(value: snapshot.data! / 100),
                                Text(snapshot.data!.toStringAsFixed(2) + " %"),
                              ]);
                            }),
                      ));
              OpenFile.open(appUpdater.localFile);
            }
          },
        ),
      ]);
    }

    return PlatformScaffold(
      appBar: appBar.getAppBar(context),
      body: ListView(
        children: children,
      ),
    );
  }
}
