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
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/navigator_key.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/theme.dart';
import 'package:provider/provider.dart';

import 'golden_helper.dart';

/// A page with its own mutable state, standing in for whatever screen the
/// user is on when they change the theme in Settings.
class _CounterPage extends StatefulWidget {
  const _CounterPage();

  @override
  State<_CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<_CounterPage> {
  int taps = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => setState(() => taps++),
          child: Text("taps: $taps"),
        ),
      ),
    );
  }
}

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() async {
    resetAppStateForGolden();
    Auth().isInitialized = false;
    Auth().loggedIn = false;
    MyTheme.themeModeNotifier.value = ThemeMode.system;
    await Settings.resetThemeColor();
  });

  testWidgets(
      "changing the theme colour in Settings updates MaterialApp in place, "
      "without losing the navigator stack or a pushed page's state",
      (tester) async {
    Auth().isInitialized = true;
    Auth().loggedIn = false;

    // Warms the real image cache first, like golden_login_test.dart does:
    // Home's own precacheImage call never resolves inside testWidgets' fake
    // time zone, which would otherwise leave an image stream listener
    // rescheduling frames forever and hang the pumps below.
    await pumpGolden(tester, const Scaffold(body: SizedBox()), dark: false);
    final warmupContext = tester.element(find.byType(Scaffold));
    await tester.runAsync(() => precacheImage(
        const AssetImage("assets/icon/icon.png"), warmupContext));

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: AppState()),
        ChangeNotifierProvider.value(value: Auth()),
      ],
      child: const MyApp(),
    ));
    await tester.pump(const Duration(milliseconds: 300));

    // Stand-in for the user being on some page (e.g. Settings) when they
    // change the theme - a restart used to tear this whole subtree down.
    navigatorKey.currentState!
        .push(MaterialPageRoute(builder: (_) => const _CounterPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final counterState =
        tester.state<_CounterPageState>(find.byType(_CounterPage));
    await tester.tap(find.descendant(
        of: find.byType(_CounterPage), matching: find.byType(ElevatedButton)));
    await tester.pump();
    expect(counterState.taps, 1);
    expect(
        Theme.of(navigatorKey.currentContext!).brightness, Brightness.light);
    // The actual re-key check: a Navigator's own GlobalKey lets it survive
    // an ancestor re-key on its own, which would make the checks above pass
    // even with one - this is the element that must not change identity.
    final materialAppElement = tester.element(find.byType(MaterialApp));

    // Same call appearance_section.dart makes. Hive-backed, like
    // MgwStorage.init() elsewhere - real I/O that never resolves inside
    // testWidgets' fake-async zone without runAsync.
    await tester.runAsync(() => MyTheme.selectThemeColor(dark));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    // Still on the pushed page, same State instance, same count - proof the
    // theme switched in place instead of re-keying MaterialApp.
    expect(find.byType(_CounterPage), findsOneWidget);
    expect(tester.state<_CounterPageState>(find.byType(_CounterPage)),
        same(counterState));
    expect(counterState.taps, 1);
    expect(tester.element(find.byType(MaterialApp)), same(materialAppElement));
    expect(
        Theme.of(navigatorKey.currentContext!).brightness, Brightness.dark);
  });
}
