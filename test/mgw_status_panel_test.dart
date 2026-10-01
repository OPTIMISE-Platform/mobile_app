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
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/services/mgw/advertisements.dart';
import 'package:mobile_app/services/mgw/reachability.dart';
import 'package:mobile_app/services/mgw/storage.dart';
import 'package:mobile_app/widgets/tabs/gateways/mgw_status_panel.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

const _pairing = "/core/api/auth-service/pairing/request";

final _mgw = MGW("192.168.1.5", "Kitchen gateway", "", "192.168.1.5",
    networkId: "network-1");

void main() {
  late FakeBackend backend;
  var probes = 0;
  var status = MgwStatus.foreign;

  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  setUp(() {
    backend = FakeBackend();
    serveGoldenBackend(backend);
    probes = 0;
    status = MgwStatus.foreign;
    MgwReachability.probeOverride = (mgw) async {
      probes++;
      return MgwReport(
          status: status,
          failedCheck:
              status == MgwStatus.foreign ? MgwFailedCheck.foreignNetwork : null,
          address: mgw.ip,
          checkedAt: DateTime.utc(2026),
          expectedNetworkId: mgw.networkId,
          advertisedNetworkId: "network-2");
    };
    AppState().networks.addAll([
      Network("network-1", "Ground floor", false, [], [],
          DeviceConnectionStatus.online, "h1", "o"),
      Network("network-2", "Garage", false, [], [],
          DeviceConnectionStatus.online, "h2", "o"),
    ]);
  });

  tearDown(() async {
    await MgwStorage.ReplacePairedMGWs([]);
    MgwReachability.probeOverride = null;
    MgwReachability.forget();
    resetGoldenBackend();
    resetAppStateForGolden();
  });

  void advertise(String networkId) =>
      backend.serveJson("GET", "/core/discovery", 200, [
        {
          "reference": MgwAdvertisements.networkReference,
          "items": {"id": networkId}
        }
      ]);

  Future<void> pumpPanel(WidgetTester tester) async {
    // Pairing again resolves the entry against the stored list first.
    await warmUpMgwStorage(tester);
    await tester.runAsync(() => MgwStorage.ReplacePairedMGWs([_mgw]));
    await pumpGolden(
        tester,
        Scaffold(
            body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: MgwStatusPanel(mgw: _mgw))),
        dark: false);
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets("pairing again with another network answering asks first",
      (tester) async {
    advertise("network-2");
    await pumpPanel(tester);

    await tester.tap(find.text("Pair again"));
    await settle(tester);
    expect(find.text("Bind to Garage?"), findsOneWidget);

    await tester.tap(find.text("Cancel"));
    await settle(tester);
    expect(backend.requests.where((r) => r.uri.path == _pairing), isEmpty);
    expect(find.text("Pairing failed"), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("pairing again is refused when the gateway serves a network "
      "this account does not have", (tester) async {
    advertise("network-9");
    await pumpPanel(tester);

    await tester.tap(find.text("Pair again"));
    await settle(tester);

    expect(find.text("Pairing failed"), findsOneWidget);
    expect(
        find.textContaining("serves a network this account does not have"),
        findsOneWidget);
    expect(backend.requests.where((r) => r.uri.path == _pairing), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("pairing again probes the gateway once afterwards",
      (tester) async {
    status = MgwStatus.unauthorized;
    advertise("network-1");
    backend.serveJson("POST", _pairing, 200,
        {"id": "id-2", "login": "login-2", "secret": "s-2"});
    await pumpPanel(tester);
    probes = 0;
    status = MgwStatus.ok;

    // Hive writes do not finish inside the fake zone, see docs/testing.md.
    final pairAgain = tester
        .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, "Pair again"))
        .onPressed!;
    await tester.runAsync(() async {
      pairAgain();
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await settle(tester);

    expect(backend.requests.where((r) => r.uri.path == _pairing), hasLength(1));
    expect(find.text("Connected"), findsOneWidget);
    expect(probes, 1);
    await tester.runAsync(() => MgwStorage.ReplacePairedMGWs([]));
    await tester.pumpWidget(const SizedBox());
  });

  List<String> pairingHosts() => backend.requests
      .where((r) => r.uri.path == _pairing)
      .map((r) => r.uri.host)
      .toList();

  testWidgets("no check starts while pairing again is under way",
      (tester) async {
    final advertisement = Completer<void>();
    backend.holds["GET /core/discovery"] = advertisement;
    advertise("network-9");
    await pumpPanel(tester);
    await tester.tap(find.text("Pair again"));
    await tester.pump();
    probes = 0;

    MgwReachability.forget();
    await tester.pump();
    await tester.pump();
    expect(probes, 0);

    advertisement.complete();
    await settle(tester);
    expect(find.text("Pairing failed"), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("with nothing advertised now, the network the last check saw "
      "decides", (tester) async {
    // No advertisement route: the gateway publishes nothing at the moment.
    await pumpPanel(tester);

    await tester.tap(find.text("Pair again"));
    await settle(tester);

    expect(find.text("Bind to Garage?"), findsOneWidget);
    await tester.tap(find.text("Cancel"));
    await settle(tester);
    expect(pairingHosts(), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("with nothing advertised at all, pairing under the stored "
      "network is asked first", (tester) async {
    status = MgwStatus.unauthorized;
    await pumpPanel(tester);

    await tester.tap(find.text("Pair again"));
    await settle(tester);

    expect(
        find.text("The gateway does not say which network it serves. Pair it "
            "for Ground floor?"),
        findsOneWidget);
    await tester.tap(find.text("Cancel"));
    await settle(tester);
    expect(pairingHosts(), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("pairing again without loaded networks says so", (tester) async {
    advertise("network-2");
    AppState().networks.clear();
    await pumpPanel(tester);

    await tester.tap(find.text("Pair again"));
    await settle(tester);

    expect(find.text("No networks are loaded yet."), findsOneWidget);
    expect(pairingHosts(), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("closing the sheet while the advertisement loads stops pairing",
      (tester) async {
    final advertisement = Completer<void>();
    backend.holds["GET /core/discovery"] = advertisement;
    advertise("network-1");
    backend.serveJson("POST", _pairing, 200,
        {"id": "id-2", "login": "login-2", "secret": "s-2"});
    await warmUpMgwStorage(tester);
    await tester.runAsync(() => MgwStorage.ReplacePairedMGWs([_mgw]));
    await pumpGolden(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showMgwStatusSheet(context, _mgw),
                child: const Text("Open"),
              ),
            ),
          ),
        ),
        dark: false);
    await tester.tap(find.text("Open"));
    await settle(tester);

    await tester.tap(find.text("Pair again"));
    await tester.pump();
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await settle(tester);
    advertisement.complete();
    await settle(tester);

    expect(pairingHosts(), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("pairing and binding anew replaces the stored entry, at the "
      "address it has now", (tester) async {
    advertise("network-2");
    backend.serveJson("POST", _pairing, 200,
        {"id": "id-2", "login": "login-2", "secret": "s-2"});
    await pumpPanel(tester);
    // The resume refresh moved the gateway after the panel opened.
    final moved = MGW(_mgw.hostname, _mgw.mDNSServiceName, _mgw.coreId,
        "192.168.1.6",
        networkId: _mgw.networkId);
    await tester.runAsync(() => MgwStorage.ReplacePairedMGWs([moved]));

    final pairAgain = tester
        .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, "Pair again"))
        .onPressed!;
    // Hive writes do not finish inside the fake zone, so the whole flow runs
    // outside it, and the dialog is answered through the navigator.
    await tester.runAsync(() async {
      pairAgain();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      tester.state<NavigatorState>(find.byType(Navigator)).pop(true);
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await settle(tester);

    final stored =
        await tester.runAsync(() => MgwStorage.LoadPairedMGWs()) ?? [];
    expect(stored.map((m) => "${m.ip}|${m.networkId}"),
        ["192.168.1.6|network-2"]);
    expect(pairingHosts(), ["192.168.1.6"]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("the panel follows its entry when the stored list changes",
      (tester) async {
    status = MgwStatus.ok;
    await pumpPanel(tester);
    expect(find.text("192.168.1.5 \u00b7 Ground floor"), findsOneWidget);

    AppState().gateways
      ..clear()
      ..add(MGW(_mgw.hostname, _mgw.mDNSServiceName, _mgw.coreId,
          "192.168.1.9",
          networkId: _mgw.networkId));
    AppState().notifyListeners();
    await settle(tester);

    expect(find.text("192.168.1.9 \u00b7 Ground floor"), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("pairing one of two entries stored before the network id split "
      "again keeps the other", (tester) async {
    Map<String, String> legacy(String host) => {
          "hostname": host,
          "mDNSServiceName": host,
          "coreId": "network-1",
          "ip": host,
        };
    await warmUpMgwStorage(tester);
    await tester.runAsync(() => Hive.box<String>("mgw.box").put(
        "connected_mgws_",
        jsonEncode([legacy("192.168.1.4"), legacy("192.168.1.5")])));
    final sibling =
        (await tester.runAsync(() => MgwStorage.LoadPairedMGWs()))![1];
    advertise("network-1");
    backend.serveJson("POST", _pairing, 200,
        {"id": "id-2", "login": "login-2", "secret": "s-2"});
    await pumpGolden(
        tester,
        Scaffold(
            body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: MgwStatusPanel(mgw: sibling))),
        dark: false);
    await tester.pump();

    final pairAgain = tester
        .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, "Pair again"))
        .onPressed!;
    await tester.runAsync(() async {
      pairAgain();
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await settle(tester);

    expect(pairingHosts(), ["192.168.1.5"]);
    final stored =
        await tester.runAsync(() => MgwStorage.LoadPairedMGWs()) ?? [];
    expect(stored.map((m) => m.ip), ["192.168.1.4", "192.168.1.5"]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("pairing again recovers from a stored list that cannot be read",
      (tester) async {
    await pumpPanel(tester);
    await tester.runAsync(() =>
        Hive.box<String>("mgw.box").put("connected_mgws_", "not json"));

    await tester.tap(find.text("Pair again"));
    await settle(tester);

    expect(find.text("Pairing failed"), findsOneWidget);
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, "Pair again"))
            .onPressed,
        isNotNull);
    await tester.pumpWidget(const SizedBox());
  });
}
