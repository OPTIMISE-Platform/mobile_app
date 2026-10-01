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

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/home.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/shared/account_epoch.dart';
import 'package:mobile_app/widgets/tabs/device_tabs.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    Auth().loggedIn = false;
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  // The sensor page and the dashboard read their configuration only when they
  // mount; a switch under mounted tabs has to mount them again.
  testWidgets("an account change under mounted tabs mounts them again",
      (tester) async {
    final backend = FakeBackend();
    backend.serveJson("GET", "/device-repository/device-groups", 200, []);
    backend.serveJson("GET", "/device-repository/extended-hubs", 200, []);
    backend.serveJson("GET", "/device-repository/extended-devices", 200, []);
    serveGoldenBackend(backend);
    await warmUpMgwStorage(tester);
    Auth().isInitialized = true;
    Auth().loggedIn = true;

    await pumpGolden(tester, const Home(), dark: false);
    final before = tester.state(find.byType(DeviceTabs));
    Auth().notifyListeners();
    await tester.pump();
    expect(tester.state(find.byType(DeviceTabs)), same(before),
        reason: "a notification alone keeps the tabs");

    AccountEpoch.advance();
    Auth().notifyListeners();
    await tester.pump();

    expect(tester.state(find.byType(DeviceTabs)), isNot(same(before)));
    await tester.pump(const Duration(seconds: 1));
  });
}
