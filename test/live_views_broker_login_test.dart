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
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/live/mqtt_connection.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/widgets/tabs/gateways/mgw_page.dart';

import 'golden_helper.dart';

/// What the dialog's probe was asked, in order.
final probes = <(String?, String?)>[];

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  final gateway = MGW('host', 'svc', 'core', '10.0.0.5', networkId: 'net-1', pairingId: 'pair-1');
  final original = brokerProbe;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    probes.clear();
  });

  tearDown(() {
    brokerProbe = original;
  });

  Future<void> openDialog(WidgetTester tester) async {
    await pumpGolden(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showBrokerLoginDialog(context, gateway),
            child: const Text('Open login'),
          ),
        ),
      ),
      dark: false,
    );
    await tester.tap(find.text('Open login'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Broker login'), findsOneWidget);
  }

  Future<void> fill(WidgetTester tester, String user, String password) async {
    await tester.enterText(find.byType(TextField).at(0), user);
    await tester.enterText(find.byType(TextField).at(1), password);
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    // The probe and the store run on the real event loop.
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets('a login the broker refuses keeps the dialog open and stores nothing', (tester) async {
    await tester.runAsync(() => saveMgwBrokerCredentials('pair-1', 'old-user', 'old-secret'));
    brokerProbe = (gw, {username, password}) async {
      probes.add((username, password));
      return LiveConnectionState.refusedNotAuthorized;
    };
    await openDialog(tester);

    // The username is prefilled from the stored login.
    expect(find.text('old-user'), findsOneWidget);

    await fill(tester, 'user', 'wrong');
    await tapSave(tester);

    expect(probes, [('user', 'wrong')]);
    expect(find.text('Broker login'), findsOneWidget, reason: 'the dialog stays open');
    expect(find.text('The broker refused this login.'), findsOneWidget);
    final stored = await tester.runAsync(() => loadMgwBrokerCredentials('pair-1'));
    expect(stored?.username, 'old-user', reason: 'a refused login is not stored');
    expect(stored?.password, 'old-secret');
  });

  testWidgets('a login the broker accepts is stored and closes the dialog', (tester) async {
    brokerProbe = (gw, {username, password}) async {
      probes.add((username, password));
      return LiveConnectionState.connected;
    };
    await openDialog(tester);

    await fill(tester, 'user', 'secret');
    await tapSave(tester);

    expect(probes, [('user', 'secret')]);
    expect(find.text('Broker login'), findsNothing);
    final stored = await tester.runAsync(() => loadMgwBrokerCredentials('pair-1'));
    expect(stored?.username, 'user');
    expect(stored?.password, 'secret');
  });

  testWidgets('an answer other than a refusal stores the login and closes the dialog', (tester) async {
    brokerProbe = (gw, {username, password}) async => LiveConnectionState.disconnected;
    await openDialog(tester);

    await fill(tester, 'user', 'secret');
    await tapSave(tester);

    expect(find.text('Broker login'), findsNothing);
    final stored = await tester.runAsync(() => loadMgwBrokerCredentials('pair-1'));
    expect(stored?.username, 'user');
  });
}
