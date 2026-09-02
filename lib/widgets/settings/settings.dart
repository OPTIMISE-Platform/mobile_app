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
import 'package:mobile_app/widgets/settings/sections/account_section.dart';
import 'package:mobile_app/widgets/settings/sections/appearance_section.dart';
import 'package:mobile_app/widgets/settings/sections/behaviour_section.dart';
import 'package:mobile_app/widgets/settings/sections/diagnostics_section.dart';
import 'package:mobile_app/widgets/settings/sections/updates_section.dart';
import 'package:mobile_app/widgets/shared/app_bar.dart';
import 'package:provider/provider.dart';

/// The settings page is a flat list of rows, so it is assembled from sections
/// rather than built in one place: it used to be a single 430-line build
/// method. Each section returns its rows including its leading divider, in the
/// order they appear.
class Settings extends StatelessWidget {
  const Settings({super.key});

  @override
  Widget build(BuildContext context) {
    const appBar = MyAppBar("Settings");

    return Consumer<AppState>(builder: (context, state, _) {
      return Scaffold(
        appBar: appBar.getAppBar(context),
        body: ListView(
          children: [
            ...appearanceSection(context, state),
            ...updatesSection(context, state),
            ...behaviourSection(context, state),
            ...diagnosticsSection(context, state),
            ...accountSection(context, state),
          ],
        ),
      );
    });
  }
}
