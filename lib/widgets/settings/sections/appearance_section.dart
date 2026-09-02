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
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/config/functions/function_config.dart';
import 'package:mobile_app/restart_controller.dart';
import 'package:mobile_app/services/settings.dart' as settings_service;
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/settings/refresh_cache_tile.dart';
import 'package:mobile_app/widgets/settings/unit_picker.dart';
import 'package:mobile_app/widgets/shared/toast.dart';
import 'package:mobile_app/widgets/tabs/nav.dart';

/// Name of the tab currently configured as the start page.
String _initialTabName() {
  final index = settings_service.Settings.getInitialTab();
  return navItems
      .firstWhere((n) => n.index == index, orElse: () => navItems.first)
      .name;
}

/// Start page, number formatting, units, cache refresh and the colour theme.
/// The first section of the page, so it does not lead with a divider.
List<Widget> appearanceSection(BuildContext context, AppState state) {
  final children = <Widget>[
    ListTile(
      title: const Text("Start Page"),
      subtitle: Text(_initialTabName()),
      onTap: () => showAdaptiveDialog(
        context: context,
        builder: (dialogContext) => AlertDialog.adaptive(
          title: const Text("Start Page"),
          content: SizedBox(
            width: double.maxFinite,
            child: StatefulBuilder(
              builder: (_, setDialogState) => ListView(
                shrinkWrap: true,
                children: navItems
                    .map((item) => ListTile(
                          leading: Icon(item.icon),
                          title: Text(item.name),
                          trailing: settings_service.Settings
                                      .getInitialTab() ==
                                  item.index
                              ? const Icon(Icons.check)
                              : null,
                          onTap: () async {
                            await settings_service.Settings
                                .setInitialTab(item.index);
                            setDialogState(() {});
                            AppState().notifyListeners();
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                          },
                        ))
                    .toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
                child: const Text("Cancel"),
                onPressed: () => Navigator.pop(dialogContext)),
          ],
        ),
      ),
    ),
    const Divider(),
    ListTile(
        title: const Text("Set Displayed Fraction Digits"),
        onTap: () => showAdaptiveDialog(
              context: context,
              builder: getDisplayedFractionsDigitSelectDialog(state),
            )),
    const Divider(),
    ListTile(
        title: const Text("Edit Units"),
        onTap: () {
          showAdaptiveDialog(
            context: context,
            builder: (context) => AlertDialog.adaptive(
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
              content: const UnitPickerList(),
              actions: [
                TextButton(
                    child: const Text("Close"),
                    onPressed: () => Navigator.pop(context)),
              ],
            ),
          );
        }),
    const Divider(),
    const RefreshCacheTile(),
  ];

  if (MyTheme.canChangeColorTheme) {
    children.addAll([
      const Divider(),
      ListTile(
        title: const Text("Choose Color"),
        onTap: () => showAdaptiveDialog(
            context: context,
            builder: (context) => AlertDialog.adaptive(
                  title: const Text("Choose Color"),
                  actions: [
                    TextButton(
                      child: const Text('Cancel'),
                      onPressed: () => Navigator.pop(context, false),
                    ),
                    TextButton(
                        child: const Text('System Default'),
                        onPressed: () async {
                          await MyTheme.selectThemeColor(null);
                          RestartController.restart();
                          if (!context.mounted) return;
                          Navigator.pop(context);
                        }),
                    TextButton(
                        child: const Text('Dark'),
                        onPressed: () async {
                          await MyTheme.selectThemeColor(dark);
                          RestartController.restart();
                          if (!context.mounted) return;
                          Navigator.pop(context);
                        }),
                    TextButton(
                        child: const Text('Light'),
                        onPressed: () async {
                          await MyTheme.selectThemeColor(light);
                          RestartController.restart();
                          if (!context.mounted) return;
                          Navigator.pop(context);
                        })
                  ],
                )),
      )
    ]);
  }

  return children;
}
