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
import 'package:mobile_app/home.dart';
import 'package:mobile_app/services/auth.dart';

import 'golden_helper.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
    Auth().isInitialized = false;
    Auth().loggedIn = false;
  });

  for (final dark in [false, true]) {
    final suffix = dark ? "dark" : "light";

    testWidgets("login screen ($suffix)", (tester) async {
      Auth().isInitialized = true;
      Auth().loggedIn = false;

      // Warms the real image cache before Home builds: the decode Future
      // Image.asset/precacheImage start during a normal pump never resolves
      // inside testWidgets' fake-time zone, even under runAsync, because the
      // resolve call itself was made in that zone. Priming the same cache key
      // for real first means Home's own resolve hits an already-completed
      // stream and paints synchronously.
      await pumpGolden(tester, const Scaffold(body: SizedBox()), dark: dark);
      final warmupContext = tester.element(find.byType(Scaffold));
      await tester.runAsync(() => precacheImage(
          const AssetImage("assets/icon/icon.png"), warmupContext));

      await pumpGolden(tester, const Home(), dark: dark);
      await expectLater(
          find.byType(MaterialApp), matchesGoldenFile("goldens/login_$suffix.png"));
    });
  }
}
