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

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/services/mgw/reachability.dart';
import 'package:mobile_app/widgets/tabs/gateways/details.dart';
import 'package:mobile_app/widgets/tabs/gateways/mgw_status_panel.dart';
import 'package:mobile_app/widgets/tabs/gateways/unpair_dialog.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

final _mgw = MGW("mgw-kitchen.local", "MGW-Core-d109d982", "d109d982",
    "192.168.1.5:8081",
    networkId: "network-1");

final _checkedAt = DateTime.utc(2026, 3, 4, 9, 30);

final _ok = MgwReport(
  status: MgwStatus.ok,
  address: "192.168.1.5:8081",
  checkedAt: _checkedAt,
  expectedNetworkId: "network-1",
  advertisedNetworkId: "network-1",
  sessionReused: true,
);

final _rejected = MgwReport(
  status: MgwStatus.unauthorized,
  failedCheck: MgwFailedCheck.rejected,
  address: "192.168.1.5:8081",
  checkedAt: _checkedAt,
  httpStatus: 401,
  gatewayMessage: "session not found",
  expectedNetworkId: "network-1",
  advertisedNetworkId: "network-1",
  sessionReused: true,
  retriedWithFreshLogin: true,
);

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  setUp(() {
    AppState().networks.add(Network("network-1", "Ground floor", false, [], [],
        DeviceConnectionStatus.online, "hash-1", "owner-1"));
  });

  tearDown(() {
    MgwReachability.probeOverride = null;
    MgwReachability.forget();
    resetGoldenBackend();
    resetAppStateForGolden();
  });

  Future<void> open(WidgetTester tester, bool dark,
      void Function(BuildContext) show) async {
    await pumpGolden(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => show(context),
              child: const Text("Open"),
            ),
          ),
        ),
      ),
      dark: dark,
    );
    await tester.tap(find.text("Open"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  for (final dark in [false, true]) {
    final suffix = dark ? "dark" : "light";

    for (final (name, report) in [("ok", _ok), ("unauthorized", _rejected)]) {
      testWidgets("status sheet $name ($suffix)", (tester) async {
        MgwReachability.forget();
        MgwReachability.probeOverride = (_) async => report;
        await open(tester, dark, (context) => showMgwStatusSheet(context, _mgw));
        expect(find.text("Check again"), findsOneWidget);
        await expectLater(find.byType(MaterialApp),
            matchesGoldenFile("goldens/mgw_status_sheet_${name}_$suffix.png"));
      });
    }

    testWidgets("unpair dialog ($suffix)", (tester) async {
      await open(tester, dark, (context) => confirmRemovePairing(context, _mgw));
      expect(find.text("Remove pairing?"), findsOneWidget);
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile("goldens/mgw_unpair_dialog_$suffix.png"));
    });
  }

  // Light and dark in one test: the module list is a request, see
  // docs/testing.md.
  testWidgets("gateway detail with status", (tester) async {
    final backend = FakeBackend();
    backend.serveJson("GET", "/core/api/module-manager/modules-reduced", 200,
        jsonDecode(File("test/fixtures/mgw_modules_reduced.json").readAsStringSync()));
    serveGoldenBackend(backend);
    await warmUpMgwStorage(tester);
    MgwReachability.probeOverride = (_) async => _rejected;

    for (final dark in [false, true]) {
      MgwReachability.forget();
      await pumpGolden(tester, MGWDetail(mgw: _mgw), dark: dark);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text("Modules"), findsOneWidget);
      await expectLater(find.byType(MaterialApp),
          matchesGoldenFile("goldens/mgw_detail_${dark ? "dark" : "light"}.png"));
    }
  });
}
