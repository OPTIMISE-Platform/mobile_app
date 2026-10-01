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
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/services/mgw/advertisements.dart';
import 'package:mobile_app/services/mgw/discovery.dart';
import 'package:mobile_app/services/mgw/reachability.dart';
import 'package:mobile_app/widgets/tabs/gateways/mgw_page.dart';
import 'package:mobile_app/widgets/tabs/gateways/mgw_status_panel.dart';
import 'package:mobile_app/widgets/tabs/gateways/gateways.dart';
import 'package:mobile_app/widgets/tabs/networks/device_networks.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

final _mgw = MGW("mgw-kitchen.local", "Kitchen gateway", "d109d982",
    "192.168.1.5:8081",
    networkId: "network-1");

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  setUp(() {
    MgwReachability.probeOverride = (mgw) async => MgwReport(
        status: MgwStatus.unauthorized,
        failedCheck: MgwFailedCheck.rejected,
        address: mgw.ip,
        checkedAt: DateTime.utc(2026),
        httpStatus: 401);
  });

  tearDown(() {
    MgwDiscoveryService.discoverOverride = null;
    resetGoldenBackend();
    MgwReachability.probeOverride = null;
    MgwReachability.forget();
    resetAppStateForGolden();
  });

  testWidgets("the trash button asks before removing a pairing",
      (tester) async {
    AppState().gateways.add(_mgw);
    await pumpGolden(tester, const Scaffold(body: Gateways()), dark: false);

    await tester.tap(find.byTooltip("Remove pairing"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("Remove pairing?"), findsOneWidget);

    await tester.tap(find.text("Cancel"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("Remove pairing?"), findsNothing);
    expect(AppState().gateways, [_mgw]);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("the gateway control of a network row opens its status",
      (tester) async {
    AppState().networks.add(Network("network-1", "Ground floor", false, [],
        [], DeviceConnectionStatus.online, "hash-1", "owner-1"));
    AppState().gateways.add(_mgw);
    await pumpGolden(tester, const Scaffold(body: DeviceListByNetwork()),
        dark: false);

    await tester.tap(find.byTooltip("Gateway status"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text("Kitchen gateway"), findsOneWidget);
    expect(find.text("Rejected - pair again"), findsOneWidget);
    expect(find.text("401"), findsOneWidget);
    expect(find.text("Check again"), findsOneWidget);
    expect(find.text("Remove pairing"), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("with two gateways in a network the row shows the routed one, "
      "and the sheet opens the other", (tester) async {
    final first = MGW("mgw-a.local", "Gateway A", "a", "192.168.1.4",
        networkId: "network-1", pairingId: "pairing-a");
    final routed = MGW("mgw-b.local", "Gateway B", "b", "192.168.1.5",
        networkId: "network-1", pairingId: "pairing-b");
    MgwReachability.probeOverride = (mgw) async => MgwReport(
        status: mgw.pairingId == routed.pairingId
            ? MgwStatus.ok
            : MgwStatus.unauthorized,
        address: mgw.ip,
        checkedAt: DateTime.utc(2026));
    AppState().networks.add(Network("network-1", "Ground floor", false, [],
        [], DeviceConnectionStatus.online, "hash-1", "owner-1")
      ..localGateways = [routed]);
    AppState().gateways.addAll([first, routed]);
    await pumpGolden(tester, const Scaffold(body: DeviceListByNetwork()),
        dark: false);

    await tester.tap(find.byTooltip("Gateway status"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text("Gateway B"), findsOneWidget);
    expect(find.text("Connected"), findsOneWidget);
    expect(find.text("Other gateways in this network"), findsOneWidget);

    await tester.tap(find.text("Gateway A"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text("192.168.1.4 \u00b7 Ground floor"), findsOneWidget);
    expect(find.text("Rejected - pair again"), findsOneWidget);
    expect(find.text("Gateway B"), findsOneWidget,
        reason: "the routed gateway is listed in its place");
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("an address refresh while the sheet is open updates the other "
      "gateway's row", (tester) async {
    final first = MGW("mgw-a.local", "Gateway A", "a", "192.168.1.4",
        networkId: "network-1", pairingId: "pairing-a");
    final routed = MGW("mgw-b.local", "Gateway B", "b", "192.168.1.5",
        networkId: "network-1", pairingId: "pairing-b");
    AppState().networks.add(Network("network-1", "Ground floor", false, [],
        [], DeviceConnectionStatus.online, "hash-1", "owner-1")
      ..localGateways = [routed]);
    AppState().gateways.addAll([first, routed]);
    await pumpGolden(tester, const Scaffold(body: DeviceListByNetwork()),
        dark: false);
    await tester.tap(find.byTooltip("Gateway status"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text("192.168.1.4"), findsOneWidget);

    // What loadStoredMGWs leaves after the refresh: new instances.
    AppState().gateways
      ..clear()
      ..addAll([
        MGW(first.hostname, first.mDNSServiceName, first.coreId, "192.168.1.14",
            networkId: first.networkId, pairingId: first.pairingId),
        MGW(routed.hostname, routed.mDNSServiceName, routed.coreId,
            routed.ip,
            networkId: routed.networkId, pairingId: routed.pairingId),
      ]);
    AppState().notifyListeners();
    await tester.pump();

    expect(find.text("192.168.1.14"), findsOneWidget);
    expect(find.text("192.168.1.4"), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("a sheet opened with an older copy shows the stored entry",
      (tester) async {
    final stale = MGW("mgw-a.local", "Gateway A", "a", "192.168.1.4",
        networkId: "network-1", pairingId: "pairing-a");
    AppState().gateways.add(MGW(stale.hostname, stale.mDNSServiceName,
        stale.coreId, "192.168.1.14",
        networkId: stale.networkId, pairingId: stale.pairingId));
    await pumpGolden(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showMgwStatusSheet(context, stale),
                child: const Text("Open"),
              ),
            ),
          ),
        ),
        dark: false);
    await tester.tap(find.text("Open"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text("192.168.1.14 \u00b7 network-1"), findsOneWidget);
    expect(find.text("192.168.1.4 \u00b7 network-1"), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  DiscoveredGateway found(String name, String ip) => DiscoveredGateway(
      coreId: name, name: name, hostname: "$name.local", ip: ip, port: 8080);

  testWidgets("gateways show while the search is still running",
      (tester) async {
    final scan = Completer<List<DiscoveredGateway>>();
    MgwDiscoveryService.discoverOverride = (onUpdate) {
      onUpdate?.call([found("first", "10.0.0.1")]);
      return scan.future;
    };
    await pumpGolden(tester, const AddLocalNetwork(), dark: false);

    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text("first"), findsOneWidget);

    scan.complete([found("first", "10.0.0.1"), found("second", "10.0.0.2")]);
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text("second"), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("while one gateway pairs, the others cannot be paired",
      (tester) async {
    final backend = FakeBackend();
    final advertisement = Completer<void>();
    backend.holds["GET /core/discovery"] = advertisement;
    backend.serveJson("GET", "/core/discovery", 200, [
      {
        "reference": MgwAdvertisements.networkReference,
        "items": {"id": "network-1"}
      }
    ]);
    backend.serveJson("POST", "/core/api/auth-service/pairing/request", 500,
        "no credential session open",
        contentType: "text/plain");
    serveGoldenBackend(backend);
    AppState().networks.add(Network("network-1", "Ground floor", false, [],
        [], DeviceConnectionStatus.online, "hash-1", "owner-1"));
    MgwDiscoveryService.discoverOverride =
        (_) async => [found("first", "10.0.0.1"), found("second", "10.0.0.2")];
    await pumpGolden(tester, const AddLocalNetwork(), dark: false);

    await tester.tap(find.widgetWithText(FilledButton, "Pair").first);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final others = tester
        .widgetList<FilledButton>(find.widgetWithText(FilledButton, "Pair"));
    expect(others, hasLength(1));
    expect(others.single.onPressed, isNull);
    expect(
        tester
            .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.refresh))
            .onPressed,
        isNull);

    advertisement.complete();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text("Pairing failed"), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("an entry added by address does not mark a discovered gateway "
      "at that address as paired", (tester) async {
    AppState().gateways.add(
        MGW("10.0.0.2", "10.0.0.2", "", "10.0.0.2", networkId: "network-1"));
    MgwDiscoveryService.discoverOverride =
        (_) async => [found("second", "10.0.0.2")];
    await pumpGolden(tester, const AddLocalNetwork(), dark: false);

    expect(find.text("Paired"), findsNothing);
    expect(find.widgetWithText(FilledButton, "Pair"), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("a paired gateway in the list can be paired again",
      (tester) async {
    AppState().gateways.add(
        MGW("first.local", "first", "first", "10.0.0.1", networkId: "n1"));
    MgwDiscoveryService.discoverOverride =
        (_) async => [found("first", "10.0.0.1")];
    await pumpGolden(tester, const AddLocalNetwork(), dark: false);

    expect(find.text("Paired"), findsOneWidget);
    final again = tester
        .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, "Pair again"));
    expect(again.onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("an address typed with scheme and path is stored without them, "
      "and one that is no address is refused in the dialog", (tester) async {
    final backend = FakeBackend();
    serveGoldenBackend(backend);
    MgwDiscoveryService.discoverOverride = (_) async => [];
    await pumpGolden(tester, const AddLocalNetwork(), dark: false);

    await tester.tap(find.text("Enter address"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), "http://");
    await tester.tap(find.text("Continue"));
    await tester.pump();
    expect(find.text("Enter a host name or IP address, optionally with a port."),
        findsOneWidget);

    await tester.enterText(
        find.byType(TextField), "http://192.168.1.5:8081/core/");
    await tester.tap(find.text("Continue"));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byType(TextField), findsNothing);
    final asked = backend.requests.single.uri;
    expect("${asked.host}:${asked.port}${asked.path}",
        "192.168.1.5:8081/core/discovery");
    await tester.pumpWidget(const SizedBox());
  });
}
