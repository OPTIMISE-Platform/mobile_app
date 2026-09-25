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
import 'package:mobile_app/services/app_update.dart';
import 'package:mobile_app/services/settings.dart' as settings_service;
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/widgets/settings/settings_section.dart';
import 'package:mobile_app/widgets/shared/grouped_list_tile.dart';
import 'package:mobile_app/widgets/shared/toast.dart';

/// The update check, on the platforms that support it at all.
SettingsSection updatesSection(BuildContext context, AppState state) {
  if (!AppUpdater.updateSupported) return const SettingsSection("Updates", []);
  return SettingsSection.of("Updates", [
    (
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
                } catch (e, s) {
                  // updateAvailable answers a failed request with null, so what
                  // arrives here is something else entirely - and the clause on
                  // ApiUnavailableException that used to stand here could not
                  // match either, that exception only ever comes wrapped.
                  ErrorReporter.log("Error checking for updates", e, s);
                  Toast.showToastNoContext(ErrorReporter.isOffline(e)
                      ? ErrorReporter.offlineMessage
                      : "Error checking for updates");
                  return;
                }
                if (updateAvailable == false) {
                  Toast.showToastNoContext("Already up to date!");
                  return;
                } else if (updateAvailable == null) {
                  Toast.showToastNoContext("Please check again later");
                  return;
                } else {
                  if (!context.mounted) return;
                  AppUpdater.showUpdateDialog(context);
                }
              },
      ),
      GroupedListTile.insetNoLeading
    ),
  ]);
}
