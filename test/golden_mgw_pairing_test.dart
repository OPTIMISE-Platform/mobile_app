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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/services/mgw/advertisements.dart';
import 'package:mobile_app/services/mgw/discovery.dart';
import 'package:mobile_app/widgets/tabs/gateways/mgw_page.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

final _kitchen = DiscoveredGateway(
    coreId: "d109d982",
    name: "MGW-Core-d109d982",
    hostname: "mgw-kitchen.local",
    ip: "192.168.1.5",
    port: 8081);

final _garage = DiscoveredGateway(
    coreId: "7f3a91c0",
    name: "MGW-Core-7f3a91c0",
    hostname: "mgw-garage.local",
    ip: "192.168.1.23",
    port: 8080);

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    MgwDiscoveryService.discoverOverride = null;
    resetGoldenBackend();
    resetAppStateForGolden();
  });

  // The extra pump lets the app bar actions finish fading to enabled once a
  // search has ended.
  Future<void> capture(WidgetTester tester, String name, bool dark) async {
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(find.byType(MaterialApp),
        matchesGoldenFile("goldens/${name}_${dark ? "dark" : "light"}.png"));
  }

  for (final dark in [false, true]) {
    final suffix = dark ? "dark" : "light";

    testWidgets("pairing page searching ($suffix)", (tester) async {
      final scan = Completer<List<DiscoveredGateway>>();
      MgwDiscoveryService.discoverOverride = (_) => scan.future;
      await pumpGolden(tester, const AddLocalNetwork(), dark: dark);
      await capture(tester, "mgw_pairing_searching", dark);
      scan.complete([]);
      await tester.pump();
    });

    testWidgets("pairing page found ($suffix)", (tester) async {
      MgwDiscoveryService.discoverOverride = (_) async => [_kitchen, _garage];
      // The kitchen gateway is paired already, so its row shows that.
      AppState().gateways.add(MGW(_kitchen.hostname, _kitchen.name,
          _kitchen.coreId, _kitchen.address,
          networkId: "network-1"));
      await pumpGolden(tester, const AddLocalNetwork(), dark: dark);
      expect(find.text("Paired"), findsOneWidget);
      expect(find.text("Pair"), findsOneWidget);
      await capture(tester, "mgw_pairing_found", dark);
    });

    testWidgets("pairing page empty ($suffix)", (tester) async {
      MgwDiscoveryService.discoverOverride = (_) async => [];
      await pumpGolden(tester, const AddLocalNetwork(), dark: dark);
      expect(find.text("No gateway found"), findsOneWidget);
      await capture(tester, "mgw_pairing_empty", dark);
    });
  }

  // Light and dark in one test: the pairing makes requests, see
  // docs/testing.md.
  testWidgets("pairing page pairing error", (tester) async {
    final backend = FakeBackend();
    backend.serveJson("GET", "/core/discovery", 200, [
      {
        "reference": MgwAdvertisements.networkReference,
        "items": {"id": "network-1"}
      }
    ]);
    backend.serveJson(
        "POST", "/core/api/auth-service/pairing/request", 500,
        "no credential session open",
        contentType: "text/plain");
    serveGoldenBackend(backend);
    AppState().networks.add(Network("network-1", "Ground floor", false, [],
        [], DeviceConnectionStatus.online, "hash-1", "owner-1"));
    MgwDiscoveryService.discoverOverride = (_) async => [_garage];

    for (final dark in [false, true]) {
      await pumpGolden(tester, const AddLocalNetwork(), dark: dark);
      await tester.tap(find.text("Pair"));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text("Pairing failed"), findsOneWidget);
      await capture(tester, "mgw_pairing_error", dark);
    }
    expect(
        backend.requests.where(
            (r) => r.uri.path == "/core/api/auth-service/pairing/request"),
        hasLength(2));
  });
}
