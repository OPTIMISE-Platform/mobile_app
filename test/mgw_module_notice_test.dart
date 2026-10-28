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
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/services/mgw/reachability.dart';
import 'package:mobile_app/services/mgw/storage.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/widgets/tabs/gateways/mgw_status_panel.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

const _modules = "/core/api/module-manager/modules-reduced";
const _deviceCommand = "github.com/SENERGY-Platform/mgw-device-command";
const _lastValue = "github.com/SENERGY-Platform/mgw-last-value-module";

final _mgw = MGW("mgw-kitchen.local", "Kitchen gateway", "d109d982",
    "192.168.1.5:8081",
    networkId: "network-1");

List<Map<String, dynamic>> _installed(List<String> ids) =>
    [for (final id in ids) {"id": id, "name": id}];

void main() {
  late FakeBackend backend;
  late List<String> toasts;
  var status = MgwStatus.ok;

  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  setUp(() {
    backend = FakeBackend();
    serveGoldenBackend(backend);
    // The migration the first credential read starts belongs to one test's
    // zone and does not complete in the next.
    MgwStorage.restartForTest();
    toasts = [];
    ErrorReporter.present = toasts.add;
    status = MgwStatus.ok;
    MgwReachability.probeOverride = (mgw) async => MgwReport(
        status: status, address: mgw.ip, checkedAt: DateTime.utc(2026));
  });

  tearDown(() {
    ErrorReporter.present = (_) {};
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

  int moduleRequests() => backend.requests.where((r) => r.uri.path == _modules).length;

  testWidgets("without Device Command the panel says so", (tester) async {
    backend.serveJson("GET", _modules, 200, _installed([_lastValue]));
    await pumpPanel(tester);

    expect(find.text("Device Command is not installed"), findsOneWidget);
    expect(
        find.textContaining("missing while it is unreachable"), findsOneWidget);
    expect(find.text("Last Value is not installed"), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("without Last Value the panel says so", (tester) async {
    backend.serveJson("GET", _modules, 200, _installed([_deviceCommand]));
    await pumpPanel(tester);

    expect(find.text("Last Value is not installed"), findsOneWidget);
    expect(find.textContaining("no values for event services"), findsOneWidget);
    expect(find.text("Device Command is not installed"), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("with both modules the panel shows no notice", (tester) async {
    backend.serveJson(
        "GET", _modules, 200, _installed([_deviceCommand, _lastValue]));
    await pumpPanel(tester);

    expect(moduleRequests(), 1);
    expect(find.textContaining("is not installed"), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("a module list that cannot be read shows nothing and no toast",
      (tester) async {
    backend.serveJson("GET", _modules, 500, {"msg": "boom"});
    await pumpPanel(tester);

    expect(moduleRequests(), 1);
    expect(find.textContaining("is not installed"), findsNothing);
    expect(toasts, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("nothing is shown while the list loads", (tester) async {
    backend.serveJson("GET", _modules, 200, _installed([]));
    final hold = backend.holds["GET $_modules"] = Completer<void>();
    await pumpPanel(tester);
    expect(moduleRequests(), 1);
    expect(find.textContaining("is not installed"), findsNothing);

    hold.complete();
    await settle(tester);
    expect(find.text("Device Command is not installed"), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("a gateway that does not answer is not asked for its modules",
      (tester) async {
    status = MgwStatus.unreachable;
    backend.serveJson("GET", _modules, 200, _installed([]));
    await pumpPanel(tester);

    expect(moduleRequests(), 0);
    expect(find.textContaining("is not installed"), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("Check again reads the modules again", (tester) async {
    backend.serveJson("GET", _modules, 200, _installed([]));
    await pumpPanel(tester);
    expect(moduleRequests(), 1);
    expect(find.text("Device Command is not installed"), findsOneWidget);

    backend.serveJson(
        "GET", _modules, 200, _installed([_deviceCommand, _lastValue]));
    await tester.tap(find.text("Check again"));
    await settle(tester);

    expect(moduleRequests(), 2);
    expect(find.textContaining("is not installed"), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("a gateway that turns ok after Check again is asked once",
      (tester) async {
    status = MgwStatus.unreachable;
    backend.serveJson("GET", _modules, 200, _installed([]));
    await pumpPanel(tester);
    expect(moduleRequests(), 0);

    status = MgwStatus.ok;
    await tester.tap(find.text("Check again"));
    await settle(tester);

    expect(moduleRequests(), 1);
    expect(find.text("Device Command is not installed"), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
