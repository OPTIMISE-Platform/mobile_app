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

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:intl/intl.dart';
import 'package:mobile_app/main.dart';
import 'package:mobile_app/services/app_update.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/services/haptic_feedback_proxy.dart';
import 'package:open_file/open_file.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:numberpicker/numberpicker.dart';

import '../../app_state.dart';
import '../../exceptions/no_network_exception.dart';
import '../../services/auth.dart';
import '../../theme.dart';

import 'package:mobile_app/services/settings.dart' as settings_service;

import '../shared/app_bar.dart';
import '../shared/page_spinner.dart';
import '../shared/toast.dart';

class Settings extends StatelessWidget {
  static final _format = DateFormat.yMd().add_jms();

  const Settings({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    const appBar = MyAppBar("Settings");

    return Consumer<AppState>(builder: (context, state, _) {
      final appUpdater = AppUpdater();

      final List<Widget> children = [
        ListTile(
          title: const Text("Switch Style"),
          onTap: () => MyTheme.toggleTheme(context),
        ),
        const Divider(),
        ListTile(
            title: const Text("Set Displayed Fraction Digits"),
            onTap: () => showPlatformDialog(
                  context: context,
                  builder: getDisplayedFractionsDigitSelectDialog(state),
                )),
        const Divider(),
        ListTile(
          title: const Text("Clear Cache"),
          onTap: () async {
            await CacheHelper.clearCache();
            Toast.showConfirmationToast(context, "Cache cleared, please restart App");
          },
        ),
        const Divider(),
        ListTile(
          title: const Text("Reset Tutorials"),
          onTap: () async {
            await settings_service.Settings.resetTutorials();
            Toast.showConfirmationToast(context, "Tutorials reset");
          },
        ),
      ];

      if (MyTheme.canChangeColorTheme) {
        children.addAll([
          const Divider(),
          ListTile(
            title: const Text("Choose Color"),
            onTap: () => showPlatformDialog(
                context: context,
                builder: (context) => PlatformAlertDialog(
                      title: const Text("Choose Color"),
                      actions: [
                        PlatformDialogAction(
                          child: PlatformText('Cancel'),
                          onPressed: () => Navigator.pop(context, false),
                        ),
                        PlatformDialogAction(
                            child: PlatformText('System Default'),
                            onPressed: () async {
                              await MyTheme.selectThemeColor(null);
                              (context.findAncestorStateOfType<State<MyApp>>() as MyAppState).restartApp();
                              Navigator.pop(context);
                            }),
                        PlatformDialogAction(
                            child: PlatformText('Dark'),
                            onPressed: () async {
                              await MyTheme.selectThemeColor(dark);
                              (context.findAncestorStateOfType<State<MyApp>>() as MyAppState).restartApp();
                              Navigator.pop(context);
                            }),
                        PlatformDialogAction(
                            child: PlatformText('Light'),
                            onPressed: () async {
                              await MyTheme.selectThemeColor(light);
                              (context.findAncestorStateOfType<State<MyApp>>() as MyAppState).restartApp();
                              Navigator.pop(context);
                            })
                      ],
                    )),
          )
        ]);
      }

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
                              Text("Current Build: ${appUpdater.currentBuild}"),
                              Text("Latest Build: ${appUpdater.latestBuild}"),
                              Text("Uploaded: ${_format.format(appUpdater.updateDate.toLocal())}"),
                              Text("Download size: ${(appUpdater.downloadSize / 1000000.0).toStringAsFixed(1)} MB"),
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
                stream.listen(null, onDone: () => OpenFile.open(appUpdater.localFile));
                await showPlatformDialog(
                  context: context,
                  builder: (context) => PlatformAlertDialog(
                    title: const Text("Update"),
                    content: StreamBuilder<double>(
                        stream: stream,
                        initialData: 0,
                        builder: (context, snapshot) {
                          return Column(mainAxisSize: MainAxisSize.min, children: [
                            LinearProgressIndicator(value: snapshot.data! / 100),
                            Text("${snapshot.data!.toStringAsFixed(2)} %"),
                          ]);
                        }),
                    actions: [
                      StreamBuilder<double>(
                          stream: stream,
                          initialData: 0,
                          builder: (context, snapshot) => PlatformDialogAction(
                              onPressed: snapshot.data == 100 ? () => OpenFile.open(appUpdater.localFile) : null,
                              child: PlatformText(snapshot.data == 100 ? 'Install' : 'Downloading...')))
                    ],
                  ),
                );
              }
            },
          ),
        ]);
      }
      children.addAll([
        const Divider(),
        ListTile(
          title: const Text("Vibration"),
          trailing: PlatformSwitch(
            onChanged: (bool value) async {
              await settings_service.Settings.setHapticFeedBackEnabled(value);
              state.notifyListeners();
              HapticFeedbackProxy.lightImpact();
            },
            value: settings_service.Settings.getHapticFeedBackEnabled(),
          ),
        )
      ]);
      children.addAll([
        const Divider(),
        ListTile(
            title: const Text("Show Debug Information"),
            onTap: () {
              final txt =
                  "Version: ${dotenv.env["VERSION"]}\nUsername: ${Auth().getUsername()}\nFCM Token (SHA1): ${sha1.convert(utf8.encode(state.fcmToken ?? ""))}";
              showPlatformDialog(
                context: context,
                builder: (context) => PlatformAlertDialog(
                  title: Row(children: [
                    const Text("Debug"),
                    const Spacer(),
                    PlatformIconButton(
                        icon: Icon(PlatformIcons(context).share),
                        onPressed: () => Share.share("OPTIMISE Debug Information\n$txt", subject: "OPTIMISE Debug Information"))
                  ]),
                  content: Text(
                    txt,
                    textAlign: TextAlign.left,
                  ),
                  actions: [
                    PlatformDialogAction(child: const Text("Close"), onPressed: () => Navigator.pop(context)),
                  ],
                ),
              );
            })
      ]);

      if (kDebugMode) {
        children.addAll([
          const Divider(),
          ListTile(
            leading: const Icon(Icons.bug_report),
            title: const Text("Delete FCM Token"),
            onTap: () async {
              await state.messaging.deleteToken();
              await state.messaging.getToken(vapidKey: dotenv.env["FireBaseVapidKey"]);
              Toast.showConfirmationToast(context, "OK");
            },
          ),
        ]);
      }

      if (state.loggedIn) {
        children.addAll([
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
                  await Auth().logout(context);
                } catch (e) {
                  Toast.showErrorToast(context, "Can't logout");
                }
              },
            ),
          )
        ]);
      }

      return PlatformScaffold(
        appBar: appBar.getAppBar(context),
        body: ListView(
          children: children,
        ),
      );
    });
  }
}

StatefulBuilder Function(BuildContext context) getDisplayedFractionsDigitSelectDialog(AppState state) {
  return (context) {
    var currentDisplayedFractionDigitsSetting = settings_service.Settings.getDisplayedFractionDigits();
    return StatefulBuilder(
      builder: (context, setState) => PlatformAlertDialog(
          actions: [
            PlatformDialogAction(child: const Text("OK"), onPressed: () => Navigator.pop(context)),
          ],
          content: NumberPicker(
              value: currentDisplayedFractionDigitsSetting,
              minValue: -1,
              maxValue: 21,
              step: 1,
              textMapper: (input) => input == "-1" ? "∞" : input,
              //axis: Axis.horizontal,
              onChanged: (value) => setState(() {
                    currentDisplayedFractionDigitsSetting = value;
                    settings_service.Settings.setDisplayedFractionDigits(value);
                    state.notifyListeners();
                  }))),
    );
  };
}
