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
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/home.dart';
import 'package:mobile_app/services/api_available.dart';
import 'package:mobile_app/services/auth.dart';

import 'fake_auth_server.dart';
import 'golden_helper.dart';

void main() {
  late FakeAuthServer server;
  final monotonicNow = Auth.monotonicNow;

  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  setUp(() {
    server = FakeAuthServer()..install();
    SecureStore().install();
    for (var i = 0; i < 20; i++) {
      server.codePolls.add(() async => pending());
    }
  });

  tearDown(() async {
    FakeAuthServer.uninstall();
    Auth.monotonicNow = monotonicNow;
    await Auth().resetForTest();
    ApiAvailableService.resetForTest();
    resetAppStateForGolden();
  });

  testWidgets("the code view shows the code, counts down, and Cancel or Back "
      "end the sign-in", (tester) async {
    var now = const Duration(hours: 1);
    Auth.monotonicNow = () => now;
    Auth().isInitialized = true;
    Auth().loggedIn = false;
    // The icon decodes only outside the fake zone; see golden_login_test.dart.
    await pumpGolden(tester, const Scaffold(body: SizedBox()), dark: false);
    final warmupContext = tester.element(find.byType(Scaffold));
    await tester.runAsync(() =>
        precacheImage(const AssetImage("assets/icon/icon.png"), warmupContext));
    await pumpGolden(tester, const Home(), dark: false);

    await tester.tap(find.text("Sign in with a code"));
    await tester.pump();
    await tester.pump();

    expect(find.text("ABCD-EFGH"), findsOneWidget);
    expect(find.text("https://localhost/auth/realms/test/device"),
        findsOneWidget);
    expect(find.text("Expires in 10:00"), findsOneWidget);
    expect(find.text("Copy code"), findsOneWidget);
    expect(find.text("Share link"), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);

    final shared = <Map<Object?, Object?>>[];
    const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(shareChannel,
        (call) async {
      shared.add(call.arguments as Map<Object?, Object?>);
      return "";
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, null));
    await tester.tap(find.text("Share link"));
    await tester.pump();
    final button = tester.getRect(find.ancestor(
        of: find.text("Share link"), matching: find.byType(OutlinedButton)));
    expect(shared.single["text"],
        "https://localhost/auth/realms/test/device?user_code=ABCD-EFGH");
    expect(
        Rect.fromLTWH(
            (shared.single["originX"] as num).toDouble(),
            (shared.single["originY"] as num).toDouble(),
            (shared.single["originWidth"] as num).toDouble(),
            (shared.single["originHeight"] as num).toDouble()),
        button,
        reason: "an iPad anchors the share sheet there");

    now += const Duration(seconds: 61);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text("Expires in 8:59"), findsOneWidget);
    expect(server.polls, hasLength(1), reason: "one interval passed");

    await tester.tap(find.text("Cancel"));
    await tester.pump();
    expect(find.text("ABCD-EFGH"), findsNothing);
    expect(find.text("Sign in with a code"), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(server.polls, hasLength(1), reason: "no poll after Cancel");

    await tester.tap(find.text("Sign in with a code"));
    await tester.pump();
    await tester.pump();
    expect(find.text("ABCD-EFGH"), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text("ABCD-EFGH"), findsNothing);
    expect(find.text("Sign in with a code"), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(server.polls, hasLength(1), reason: "no poll after Back");
  });

  testWidgets("a code that ends shows its message and New code",
      (tester) async {
    server.codePolls
      ..clear()
      ..add(() async => oauthError("expired_token"));
    Auth().isInitialized = true;
    Auth().loggedIn = false;
    await pumpGolden(tester, const Scaffold(body: SizedBox()), dark: false);
    final warmupContext = tester.element(find.byType(Scaffold));
    await tester.runAsync(() =>
        precacheImage(const AssetImage("assets/icon/icon.png"), warmupContext));
    await pumpGolden(tester, const Home(), dark: false);

    await tester.tap(find.text("Sign in with a code"));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();

    expect(find.text(Auth.codeExpired), findsOneWidget);
    expect(find.text("ABCD-EFGH"), findsNothing);

    await tester.tap(find.text("New code"));
    await tester.pump();
    await tester.pump();
    expect(find.text("ABCD-EFGH"), findsOneWidget);
    expect(server.deviceRequests, hasLength(2));

    await tester.tap(find.text("Cancel"));
    await tester.pump(const Duration(seconds: 10));
    expect(find.text("Sign in with a code"), findsOneWidget);
  });
}
