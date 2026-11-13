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

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_app/home.dart';
import 'package:mobile_app/services/api_available.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/settings.dart';

import 'fake_auth_server.dart';
import 'golden_helper.dart';

void main() {
  late FakeAuthServer server;
  late SecureStore store;
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });
  setUp(() async {
    server = FakeAuthServer()..install();
    store = SecureStore()..install();
    LegacyIdentityStore().install();
    Auth.serverAvailableOverride = () async => true;
    ApiAvailableService.probeOverride = () async => true;
    await Settings.setAccount("test-account");
    await Settings.setCredentialsStored(false);
    await Settings.setSignedOut(false);
  });
  tearDown(() async {
    FakeAuthServer.uninstall();
    LegacyIdentityStore.uninstall();
    Auth.serverAvailableOverride = null;
    await Auth().resetForTest();
    ApiAvailableService.resetForTest();
    resetAppStateForGolden();
  });

  testWidgets("a stored session that loads during a sign-in with a code leaves "
      "the password form for after the logout",
      (tester) async {
    final held = Completer<http.Response>();
    server.codePolls.add(() => held.future);
    store.put(credentials("stored"));
    store.readFails = true;
    await tester.runAsync(() => Auth().init());
    expect(Auth().loggedIn, isFalse);
    await pumpGolden(tester, const Scaffold(body: SizedBox()), dark: false);
    final warmupContext = tester.element(find.byType(Scaffold));
    await tester.runAsync(() =>
        precacheImage(const AssetImage("assets/icon/icon.png"), warmupContext));
    await pumpGolden(tester, const Home(), dark: false);

    await tester.tap(find.text("Sign in with a code"));
    await tester.pump();
    await tester.pump();
    expect(find.text("ABCD-EFGH"), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    expect(server.polls, hasLength(1));

    // The stored session becomes readable (as on resume after first unlock).
    store.readFails = false;
    await tester.runAsync(() => Auth().getHeaders());
    expect(Auth().loggedIn, isTrue);
    // The user confirms on the PC: the poll answers with tokens, dropped.
    held.complete(tokens("by-code"));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    }
    expect(store.stored?.accessToken, "stored");
    // Later logout (before a frame builds the tabs).
    await tester.runAsync(() => Auth().onLogoutForTest());
    expect(Auth().loggedIn, isFalse);
    await tester.pump();
    final pollsBefore = server.polls.length;
    await tester.pump(const Duration(seconds: 30));
    // The password form, not the code view of the ended sign-in.
    expect(find.text("ABCD-EFGH"), findsNothing);
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text("Sign in with a code"), findsOneWidget);
    expect(server.polls.length, pollsBefore);
    expect(find.text("New code"), findsNothing);
  });
}
