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
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/widgets/shared/page_spinner.dart';
import 'package:mobile_app/widgets/shared/toast.dart';
import 'package:provider/provider.dart';

/// Logout, only while someone is signed in.
List<Widget> accountSection(BuildContext context, AppState state) {
  if (!state.loggedIn) return const [];
  return [
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
  ];
}
