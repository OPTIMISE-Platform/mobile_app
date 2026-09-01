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
import 'package:mobile_app/widgets/settings/settings_toggle.dart';

/// The on/off settings. Each leads with its divider, so the sections of the
/// page concatenate into the same sequence they had as one list.
List<Widget> behaviourSection(BuildContext context, AppState state) => [
      const Divider(),
      SettingsToggle(
        title: "Get Pre-Releases",
        value: settings_service.Settings.getPreReleaseMode(),
        onChanged: (v) async {
          await settings_service.Settings.setPreReleaseMode(v);
          state.notifyListeners();
        },
      ),
      const Divider(),
      SettingsToggle(
        title: "Vibration",
        value: settings_service.Settings.getHapticFeedBackEnabled(),
        onChanged: (v) async {
          await settings_service.Settings.setHapticFeedBackEnabled(v);
          state.notifyListeners();
        },
      ),
      const Divider(),
      SettingsToggle(
        title: "Local Mode",
        value: settings_service.Settings.getLocalMode(),
        onChanged: (v) async {
          await settings_service.Settings.setLocalMode(v);
          state.notifyListeners();
          state.setAndGetDisabledTabs();
        },
      ),
      const Divider(),
      SettingsToggle(
        title: "Show Filter",
        value: settings_service.Settings.getFilterMode(),
        onChanged: (v) async {
          await settings_service.Settings.setFilterMode(v);
          state.notifyListeners();
        },
      ),
      const Divider(),
      SettingsToggle(
        title: "New Device Manager",
        value: settings_service.Settings.getDeviceManagerMode(),
        onChanged: (v) async {
          await settings_service.Settings.setDeviceManagerMode(v);
          state.notifyListeners();
        },
      ),
    ];
