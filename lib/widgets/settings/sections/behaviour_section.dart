/*
 * Copyright 2026 InfAI (CC SES)
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
import 'package:mobile_app/services/settings.dart' as settings_service;
import 'package:mobile_app/widgets/settings/settings_section.dart';
import 'package:mobile_app/widgets/settings/settings_toggle.dart';
import 'package:mobile_app/widgets/shared/grouped_list_tile.dart';

/// The on/off settings. Every row is a switch, so none has a leading widget.
SettingsSection behaviourSection(BuildContext context, AppState state) =>
    SettingsSection.of("Behaviour", [
      (
        SettingsToggle(
          title: "Get Pre-Releases",
          value: settings_service.Settings.getPreReleaseMode(),
          onChanged: (v) async {
            await settings_service.Settings.setPreReleaseMode(v);
            state.notifyListeners();
            await state.syncReleaseTopics();
          },
        ),
        GroupedListTile.insetNoLeading
      ),
      (
        SettingsToggle(
          title: "Vibration",
          value: settings_service.Settings.getHapticFeedBackEnabled(),
          onChanged: (v) async {
            await settings_service.Settings.setHapticFeedBackEnabled(v);
            state.notifyListeners();
          },
        ),
        GroupedListTile.insetNoLeading
      ),
      (
        SettingsToggle(
          title: "Local Mode",
          value: settings_service.Settings.getLocalMode(),
          onChanged: (v) async {
            await settings_service.Settings.setLocalMode(v);
            state.notifyListeners();
            state.setAndGetDisabledTabs();
          },
        ),
        GroupedListTile.insetNoLeading
      ),
      (
        SettingsToggle(
          title: "Show Filter",
          value: settings_service.Settings.getFilterMode(),
          onChanged: (v) async {
            await settings_service.Settings.setFilterMode(v);
            state.notifyListeners();
          },
        ),
        GroupedListTile.insetNoLeading
      ),
    ]);
