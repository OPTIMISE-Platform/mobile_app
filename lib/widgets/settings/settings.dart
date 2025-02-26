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
import 'package:isar/isar.dart';
import 'package:mobile_app/main.dart';
import 'package:mobile_app/models/exception_log_element.dart';
import 'package:mobile_app/services/app_update.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/services/haptic_feedback_proxy.dart';
import 'package:mobile_app/services/settings.dart' as settings_service;
import 'package:numberpicker/numberpicker.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/config/functions/function_config.dart';
import 'package:mobile_app/exceptions/api_unavailable_exception.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/shared/isar.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/app_bar.dart';
import 'package:mobile_app/widgets/shared/page_spinner.dart';
import 'package:mobile_app/widgets/shared/toast.dart';

class Settings extends StatelessWidget {
  Settings({super.key});

  String _functionSearch = "";

  @override
  Widget build(BuildContext context) {
    const appBar = MyAppBar("Settings");

    return Consumer<AppState>(builder: (context, state, _) {
      final List<Widget> children = [
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
                          await settings_service.Settings
                              .deleteAllFunctionPreferredCharacteristicIds();
                          reinit();
                          AppState().notifyListeners();
                          AppState().pushRefresh();
                          Toast.showToastNoContext("All Reset");
                        },
                        child: const Text("Reset All"))
                  ]),
                  content: StatefulBuilder(
                      builder: (context, setState) =>
                          _getFunctionPreferredCharacteristicsList(
                              context, setState)),
                  actions: [
                    PlatformDialogAction(
                        child: const Text("Close"),
                        onPressed: () => Navigator.pop(context)),
                  ],
                ),
              );
            }),
        const Divider(),
        ListTile(
          title: Text("Refresh Cache",
              style: settings_service.Settings.getLocalMode()
                  ? TextStyle(color: Theme.of(context).disabledColor)
                  : null),
          onTap: settings_service.Settings.getLocalMode()
              ? null
              : () async {
                  await CacheHelper.clearCache();
                  await CacheHelper.refreshCache();
                  Toast.showToastNoContext(
                      "Cache refreshed, please restart App");
                },
        ),
        const Divider(),
        ListTile(
          title: const Text("Reset Tutorials"),
          onTap: () async {
            await settings_service.Settings.resetTutorials();
            Toast.showToastNoContext("Tutorials reset");
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
                              (context.findAncestorStateOfType<State<MyApp>>()
                                      as MyAppState)
                                  .restartApp();
                              Navigator.pop(context);
                            }),
                        PlatformDialogAction(
                            child: PlatformText('Dark'),
                            onPressed: () async {
                              await MyTheme.selectThemeColor(dark);
                              (context.findAncestorStateOfType<State<MyApp>>()
                                      as MyAppState)
                                  .restartApp();
                              Navigator.pop(context);
                            }),
                        PlatformDialogAction(
                            child: PlatformText('Light'),
                            onPressed: () async {
                              await MyTheme.selectThemeColor(light);
                              (context.findAncestorStateOfType<State<MyApp>>()
                                      as MyAppState)
                                  .restartApp();
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
            title: Text("Check Updates",
                style: settings_service.Settings.getLocalMode()
                    ? TextStyle(color: Theme.of(context).disabledColor)
                    : null),
            onTap: settings_service.Settings.getLocalMode()
                ? null
                : () async {
                    late final bool? updateAvailable;
                    try {
                      updateAvailable = await AppUpdater.updateAvailable();
                    } on ApiUnavailableException {
                      Toast.showToastNoContext("Currently unavailable");
                      return;
                    } catch (e) {
                      Toast.showToastNoContext("Error checking for updates");
                      return;
                    }
                    if (updateAvailable == false) {
                      Toast.showToastNoContext("Already up to date!");
                      return;
                    } else if (updateAvailable == null) {
                      Toast.showToastNoContext("Please check again later");
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
          title: const Text("Get Pre-Releases"),
          trailing: PlatformSwitch(
            onChanged: (bool value) async {
              await settings_service.Settings.setPreReleaseMode(value);
              state.notifyListeners();
              HapticFeedbackProxy.lightImpact();
            },
            value: settings_service.Settings.getPreReleaseMode(),
          ),
        )
      ]);
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
          title: const Text("Local Mode"),
          trailing: PlatformSwitch(
            onChanged: (bool value) async {
              await settings_service.Settings.setLocalMode(value);
              state.notifyListeners();
              state.setAndGetDisabledTabs();
              HapticFeedbackProxy.lightImpact();
            },
            value: settings_service.Settings.getLocalMode(),
          ),
        )
      ]);
      children.addAll([
        const Divider(),
        ListTile(
          title: const Text("Show Filter"),
          trailing: PlatformSwitch(
            onChanged: (bool value) async {
              await settings_service.Settings.setFilterMode(value);
              state.notifyListeners();
              HapticFeedbackProxy.lightImpact();
            },
            value: settings_service.Settings.getFilterMode(),
          ),
        )
      ]);
      children.addAll([
        const Divider(),
        ListTile(
          title: const Text("New Device Manager"),
          trailing: PlatformSwitch(
            onChanged: (bool value) async {
              await settings_service.Settings.setDeviceManagerMode(value);
              state.notifyListeners();
              HapticFeedbackProxy.lightImpact();
            },
            value: settings_service.Settings.getDeviceManagerMode(),
          ),
        )
      ]);
      children.addAll([
        const Divider(),
        ListTile(
            title: const Text("Show Debug Information"),
            onTap: () async {
              var txt = "Version: ${dotenv.env["VERSION"]}\n"
                  "Username: ${Auth().getUsername()}\n"
                  "FCM Token (SHA1): ${sha1.convert(utf8.encode(state.fcmToken ?? ""))}\n"
                  "Local Mode:  ${settings_service.Settings.getLocalMode()}\n\n";
              "Keycloak Url: ${settings_service.Settings.getKeycloakUrl()}\n"
                  "Keycloak Redirect: ${settings_service.Settings.getKeycloakRedirect()}\n"
                  "Api Url: ${settings_service.Settings.getApiUrl()}\n";
              if (isar != null) {
                final ex = await isar!.exceptionLogElements.where().findAll();
                if (ex.isNotEmpty) {
                  txt += "\nException Log:\n";
                  ex.forEach((e) => txt += "$e\n\n");
                }
              }
              showPlatformDialog(
                context: context,
                builder: (context) => PlatformAlertDialog(
                  title: Row(children: [
                    const Text("Debug"),
                    const Spacer(),
                    PlatformIconButton(
                        icon: Icon(PlatformIcons(context).share),
                        onPressed: () => Share.share(
                            "OPTIMISE Debug Information\n$txt",
                            subject: "OPTIMISE Debug Information"))
                  ]),
                  content: Scrollbar(
                      child: SingleChildScrollView(
                          child: Text(
                    txt,
                    textAlign: TextAlign.left,
                  ))),
                  actions: [
                    PlatformDialogAction(
                        child: const Text("Clear Log"),
                        onPressed: () async {
                          if (isar != null) {
                            await isar!.writeTxn(() async => await isar!
                                .exceptionLogElements
                                .where()
                                .deleteAll());
                          }
                          Navigator.pop(context);
                        }),
                    PlatformDialogAction(
                        child: const Text("Close"),
                        onPressed: () => Navigator.pop(context)),
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
              await state.messaging
                  .getToken(vapidKey: dotenv.env["FireBaseVapidKey"]);
              Toast.showToastNoContext("OK");
            },
          ),
        ]);
      }

      children.addAll([
        const Divider(),
        ListTile(
          title: const Text("Server Settings"),
          onTap: () async {
            String? keycloakUrl = settings_service.Settings.getKeycloakUrl();
            String? keycloakRedirect =
                settings_service.Settings.getKeycloakRedirect();
            String? apiUrl = settings_service.Settings.getApiUrl();

            await showPlatformDialog(
              context: context,
              builder: (context) => PlatformAlertDialog(
                title: const Text("Edit Server Settings"),
                content: Column(
                  children: [
                    PlatformTextFormField(
                        hintText: "Keycloak Url",
                        initialValue: keycloakUrl,
                        keyboardType: TextInputType.url,
                        autovalidateMode: AutovalidateMode.always,
                        onChanged: (value) {
                          keycloakUrl = value;
                        }),
                    PlatformTextFormField(
                        hintText: "Keycloak Redirect",
                        initialValue: keycloakRedirect,
                        keyboardType: TextInputType.url,
                        autovalidateMode: AutovalidateMode.always,
                        onChanged: (value) {
                          keycloakRedirect = value;
                        }),
                    PlatformTextFormField(
                        hintText: "Api Url",
                        initialValue: apiUrl,
                        keyboardType: TextInputType.url,
                        autovalidateMode: AutovalidateMode.always,
                        onChanged: (value) {
                          apiUrl = value;
                        }),
                  ],
                ),
                actions: [
                  PlatformDialogAction(
                      child: const Text("Reset"),
                      onPressed: () async {
                        await settings_service.Settings.setKeycloakUrl(null);
                        await settings_service.Settings.setKeycloakRedirect(
                            null);
                        await settings_service.Settings.setApiUrl(null);
                        Toast.showToastNoContext("Reset done, consider logging out");
                        Navigator.pop(context);
                      }),
                  PlatformDialogAction(
                      child: const Text("Close"),
                      onPressed: () => Navigator.pop(context)),
                  PlatformDialogAction(
                      child: const Text("Save"),
                      onPressed: () async {
                        await settings_service.Settings.setKeycloakUrl(
                            keycloakUrl);
                        await settings_service.Settings.setKeycloakRedirect(
                            keycloakRedirect);
                        await settings_service.Settings.setApiUrl(apiUrl);
                        Navigator.pop(context);
                      }),
                ],
              ),
            );
          },
        ),
      ]);

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
                  Toast.showToastNoContext("Can't logout");
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

  Widget _getFunctionPreferredCharacteristicsList(
      BuildContext context, StateSetter setState) {
    final functions = AppState()
        .platformFunctions
        .values
        .where((f) =>
            (AppState().concepts[f.concept_id]?.characteristics ?? []).length > 1 &&
            f.name.toLowerCase().contains(_functionSearch.toLowerCase()))
        .toList();
    final list = ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: functions.length,
        itemBuilder: (context, i) {
          final f = functions[i];
          return ListTile(
              title: PlatformWidget(
                  material: (_, __) => PopupMenuButton<String?>(
                        initialValue: settings_service.Settings
                                .getFunctionPreferredCharacteristicId(f.id) ??
                            AppState().concepts[f.concept_id]?.base_characteristic_id,
                        itemBuilder: (_) => (AppState().concepts[f.concept_id]?.characteristics ?? [])
                            .map(
                              (e) => PopupMenuItem<String?>(
                                  value: e.id,
                                  child: Text(e.name)),
                            )
                            .toList()
                          ..add(PopupMenuItem<String?>(
                              value: null,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [Divider(), Text("Reset")],
                              ))),
                        onSelected: (v) {
                          settings_service.Settings
                              .setFunctionPreferredCharacteristicId(f.id, v);
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
                                  actions: AppState().concepts[f.concept_id]?.characteristics
                                      .map((e) => CupertinoActionSheetAction(
                                            isDefaultAction: (settings_service
                                                            .Settings
                                                        .getFunctionPreferredCharacteristicId(
                                                            f.id) ??
                                                AppState().concepts[f.concept_id]?.base_characteristic_id) == e.id,
                                            child: Text(e.name),
                                            onPressed: () {
                                              settings_service.Settings
                                                  .setFunctionPreferredCharacteristicId(
                                                      f.id, e.id);
                                              reinit();
                                              AppState().notifyListeners();
                                              setState(() {});
                                              AppState().pushRefresh();
                                              Navigator.pop(context);
                                            },
                                          ))
                                      .toList()
                                    ?..add(CupertinoActionSheetAction(
                                      isDestructiveAction: true,
                                      child: const Text("Reset"),
                                      onPressed: () {
                                        settings_service.Settings
                                            .setFunctionPreferredCharacteristicId(
                                                f.id, null);
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

StatefulBuilder Function(BuildContext context)
    getDisplayedFractionsDigitSelectDialog(AppState state) {
  return (context) {
    var currentDisplayedFractionDigitsSetting =
        settings_service.Settings.getDisplayedFractionDigits();
    return StatefulBuilder(
      builder: (context, setState) => PlatformAlertDialog(
          actions: [
            PlatformDialogAction(
                child: const Text("OK"),
                onPressed: () => Navigator.pop(context)),
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
