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

@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/widgets/settings/settings.dart';

import 'golden_helper.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
    Auth().loggedIn = false;
  });

  for (final dark in [false, true]) {
    final suffix = dark ? "dark" : "light";

    testWidgets("settings page ($suffix)", (tester) async {
      // Logged in, so the Logout row at the bottom of the page is included.
      Auth().loggedIn = true;
      await pumpGolden(tester, const Settings(), dark: dark);
      await expectLater(
          find.byType(MaterialApp), matchesGoldenFile("goldens/settings_$suffix.png"));
    });
  }
}
