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
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/live/mqtt_connection.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/services/mgw/reachability.dart';
import 'package:mobile_app/services/mgw/storage.dart';
import 'package:mobile_app/widgets/tabs/gateways/mgw_status_panel.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

final _mgw = MGW("mgw-kitchen.local", "Kitchen gateway", "d109d982",
    "192.168.1.5:8081",
    networkId: "network-1", pairingId: "pair-1");

void main() {
  late List<(String?, String?)> probes;
  late FutureOr<LiveConnectionState> Function() answer;

  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    serveGoldenBackend(FakeBackend());
    MgwStorage.restartForTest();
    MgwReachability.probeOverride = (mgw) async => MgwReport(
        status: MgwStatus.unreachable,
        address: mgw.ip,
        checkedAt: DateTime.utc(2026));
    probes = [];
    answer = () => LiveConnectionState.connected;
    brokerProbe = (gw, {username, password}) async {
      probes.add((username, password));
      return answer();
    };
  });

  tearDown(() {
    brokerProbe = probeMgwBroker;
    MgwStatusPanel.forgetBrokerChecks();
    MgwReachability.probeOverride = null;
    MgwReachability.forget();
    resetGoldenBackend();
    resetAppStateForGolden();
  });

  Future<void> pumpPanel(WidgetTester tester) async {
    await warmUpMgwStorage(tester);
    await pumpGolden(
        tester,
        Scaffold(
            body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: MgwStatusPanel(mgw: _mgw))),
        dark: false);
    await settle(tester);
  }

  String brokerRow(WidgetTester tester) {
    final row = find.ancestor(
        of: find.text("Message broker"), matching: find.byType(Row));
    return tester
        .widgetList<SelectableText>(
            find.descendant(of: row, matching: find.byType(SelectableText)))
        .single
        .data!;
  }

  testWidgets("a broker that accepts the stored login says so", (tester) async {
    await tester.runAsync(() => saveMgwBrokerCredentials("pair-1", "user", "secret"));
    await pumpPanel(tester);

    expect(probes, [("user", "secret")]);
    expect(brokerRow(tester), "Connected with the stored login");
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("a broker that wants a login, with none stored, says so", (tester) async {
    answer = () => LiveConnectionState.refusedNotAuthorized;
    await pumpPanel(tester);

    expect(probes, [(null, null)]);
    expect(brokerRow(tester), "Asks for a login, none is stored");
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("a refused stored login is told apart from a missing one", (tester) async {
    await tester.runAsync(() => saveMgwBrokerCredentials("pair-1", "user", "wrong"));
    answer = () => LiveConnectionState.refusedNotAuthorized;
    await pumpPanel(tester);

    expect(brokerRow(tester), "Refused the stored login");
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("a broker that does not answer names the address asked", (tester) async {
    answer = () => LiveConnectionState.disconnected;
    await pumpPanel(tester);

    expect(brokerRow(tester), "Not answering at 192.168.1.5:1883");
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("a probe that fails in the app says it could not check", (tester) async {
    answer = () => throw StateError("no storage");
    await pumpPanel(tester);

    expect(brokerRow(tester), "Could not be checked");
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("the row says it is checking until the broker answers, and "
      "Check again asks again", (tester) async {
    final pending = Completer<LiveConnectionState>();
    answer = () => pending.future;
    await pumpPanel(tester);
    expect(brokerRow(tester), "Checking...");

    pending.complete(LiveConnectionState.disconnected);
    await settle(tester);
    expect(brokerRow(tester), "Not answering at 192.168.1.5:1883");

    answer = () => LiveConnectionState.connected;
    await tester.tap(find.text("Check again"));
    await settle(tester);
    expect(probes.length, 2);
    expect(brokerRow(tester), "Connected");
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("a login saved elsewhere while the panel is open is checked "
      "again", (tester) async {
    answer = () => LiveConnectionState.refusedNotAuthorized;
    await pumpPanel(tester);
    expect(brokerRow(tester), "Asks for a login, none is stored");

    // As the login dialog that pairing opens on its own does.
    answer = () => LiveConnectionState.connected;
    await tester.runAsync(() => saveMgwBrokerCredentials("pair-1", "user", "secret"));
    await settle(tester);

    expect(probes, [(null, null), ("user", "secret")]);
    expect(brokerRow(tester), "Connected with the stored login");
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("an address that serves another network is not probed",
      (tester) async {
    MgwReachability.probeOverride = (mgw) async => MgwReport(
        status: MgwStatus.foreign,
        address: mgw.ip,
        checkedAt: DateTime.utc(2026));
    await pumpPanel(tester);

    expect(brokerRow(tester), MgwStatusText.brokerOfForeign);
    expect(probes, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("reopening within a minute shows the last answer without a "
      "new connection", (tester) async {
    await pumpPanel(tester);
    expect(probes, hasLength(1));
    await tester.pumpWidget(const SizedBox());

    answer = () => LiveConnectionState.refusedOther;
    await pumpPanel(tester);
    expect(probes, hasLength(1));
    expect(brokerRow(tester), "Connected");
    await tester.pumpWidget(const SizedBox());
  });
}

// The stored login is read on the real event loop.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}
