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
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:mobile_app/main.dart';
import 'package:mobile_app/services/app_update.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/services/haptic_feedback_proxy.dart';
import 'package:mobile_app/services/settings.dart' as settings_service;
import 'package:numberpicker/numberpicker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app_state.dart';
import '../../config/functions/function_config.dart';
import '../../exceptions/no_network_exception.dart';
import '../../services/auth.dart';
import '../../theme.dart';
import '../shared/app_bar.dart';
import '../shared/page_spinner.dart';
import '../shared/toast.dart';

class Settings extends StatelessWidget {
  Settings({Key? key}) : super(key: key);

  String _functionSearch = "";

  @override
  Widget build(BuildContext context) {
    const appBar = MyAppBar("Settings");

    return Consumer<AppState>(builder: (context, state, _) {
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
            title: const Text("Edit Units"),
            onTap: () {
              showPlatformDialog(
                context: context,
                builder: (context) => PlatformAlertDialog(
                  title: Row(children: [
                    const Text("Edit Units"),
                    const Spacer(),
                    OutlinedButton(
                        onPressed: () async {
                          await settings_service.Settings.deleteAllFunctionPreferredCharacteristicIds();
                          reinit();
                          AppState().notifyListeners();
                          AppState().pushRefresh();
                          Toast.showConfirmationToast(context, "All Reset");
                        },
                        child: const Text("Reset All"))
                  ]),
                  content: StatefulBuilder(builder: (context, setState) => _getFunctionPreferredCharacteristicsList(context, setState)),
                  actions: [
                    PlatformDialogAction(child: const Text("Close"), onPressed: () => Navigator.pop(context)),
                  ],
                ),
              );
            }),
        const Divider(),
        ListTile(
          title: const Text("Refresh Cache"),
          onTap: () async {
            await CacheHelper.clearCache();
            await CacheHelper.refreshCache();
            Toast.showConfirmationToast(context, "Cache refreshed, please restart App");
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

      if (AppUpdater.updateSupported) {
        children.addAll([
          const Divider(),
          ListTile(
            title: const Text("Check Updates"),
            onTap: () async {
              late final bool? updateAvailable;
              try {
                updateAvailable = await AppUpdater.updateAvailable();
              } on NoNetworkException {
                Toast.showWarningToast(context, "Currently offline");
                return;
              } catch (e) {
                Toast.showErrorToast(context, "Error checking for updates");
                return;
              }
              if (updateAvailable == false) {
                Toast.showConfirmationToast(context, "Already up to date!");
                return;
              } else if (updateAvailable == null) {
                Toast.showWarningToast(context, "Please check again later");
                return;
              } else {
                AppUpdater.showUpdateDialog(context);
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

  Widget _getFunctionPreferredCharacteristicsList(BuildContext context, StateSetter setState) {
    final functions = AppState()
        .nestedFunctions
        .values
        .where((f) => (f.concept.characteristic_ids ?? []).length > 1 && f.name.toLowerCase().contains(_functionSearch.toLowerCase()))
        .toList();
    final list = ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: functions.length,
        itemBuilder: (context, i) {
          final f = functions[i];
          return ListTile(
              title: PlatformWidget(
                  material: (_, __) => PopupMenuButton<String?>(
                        initialValue: settings_service.Settings.getFunctionPreferredCharacteristicId(f.id) ?? f.concept.base_characteristic_id,
                        itemBuilder: (_) => f.concept.characteristic_ids!
                            .map(
                              (e) =>
                                  PopupMenuItem<String?>(value: e, child: Text(AppState().characteristics[e]?.name ?? "MISSING_CHARACTERISTIC_NAME")),
                            )
                            .toList()
                          ..add(PopupMenuItem<String?>(
                              value: null,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [Divider(), Text("Reset")],
                              ))),
                        onSelected: (v) {
                          settings_service.Settings.setFunctionPreferredCharacteristicId(f.id, v);
                          reinit();
                          AppState().notifyListeners();
                          AppState().pushRefresh();
                          setState(() {});
                        },
                        child: Text(f.name),
                      ),
                  cupertino: (_, __) => GestureDetector(
                        onTap: () => showPlatformModalSheet(
                            context: context,
                            builder: (context) => CupertinoActionSheet(
                                  actions: f.concept.characteristic_ids!
                                      .map((e) => CupertinoActionSheetAction(
                                            isDefaultAction: (settings_service.Settings.getFunctionPreferredCharacteristicId(f.id) ??
                                                    f.concept.base_characteristic_id) ==
                                                e,
                                            child: Text(AppState().characteristics[e]?.name ?? "MISSING_CHARACTERISTIC_NAME"),
                                            onPressed: () {
                                              settings_service.Settings.setFunctionPreferredCharacteristicId(f.id, e);
                                              reinit();
                                              AppState().notifyListeners();
                                              setState(() {});
                                              AppState().pushRefresh();
                                              Navigator.pop(context);
                                            },
                                          ))
                                      .toList()
                                    ..add(CupertinoActionSheetAction(
                                      isDestructiveAction: true,
                                      child: const Text("Reset"),
                                      onPressed: () {
                                        settings_service.Settings.setFunctionPreferredCharacteristicId(f.id, null);
                                        reinit();
                                        AppState().notifyListeners();
                                        setState(() {});
                                        AppState().pushRefresh();
                                        Navigator.pop(context);
                                      },
                                    )),
                                )),
                        child: Text(f.name),
                      )));
        });
    final column = SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              padding: MyTheme.inset,
              child: TextFormField(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Search',
                ),
                onChanged: (filter) {
                  _functionSearch = filter;
                  setState(() {});
                },
                initialValue: _functionSearch,
              )),
          Expanded(child: Scrollbar(child: list))
        ]));
    return PlatformWidget(
      cupertino: (_, __) => Material(
        child: column,
      ),
      material: (_, __) => column,
    );
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
