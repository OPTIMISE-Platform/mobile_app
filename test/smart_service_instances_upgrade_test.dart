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
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/tabs/smart-services/instances.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

const _repo = "/smart-services/repository";

Map<String, dynamic> _instanceJson(String id, String name) => {
      "description": "",
      "design_id": "design-1",
      "id": id,
      "name": name,
      "release_id": "rel-old",
      "user_id": "user-1",
      "error": null,
      "ready": true,
      "parameters": [],
      "deleting": false,
      "new_release_id": "rel-new",
    };

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  testWidgets(
      "a refresh that reorders the list keeps the upgrade with the instance "
      "it was started for", (tester) async {
    final backend = FakeBackend();
    backend.serveJson("GET", "$_repo/instances", 200,
        [_instanceJson("inst-a", "Instance A"), _instanceJson("inst-b", "Instance B")]);
    backend.serveJson("GET", "$_repo/releases/rel-new/parameters", 200, []);
    backend.serveJson("PUT", "$_repo/instances/inst-a/parameters", 200,
        _instanceJson("inst-a", "Instance A"));
    backend.serveJson("PUT", "$_repo/instances/inst-b/parameters", 200,
        _instanceJson("inst-b", "Instance B"));
    final releaseParameters = Completer<void>();
    backend.holds["GET $_repo/releases/rel-new/parameters"] = releaseParameters;
    serveGoldenBackend(backend);

    await pumpGolden(tester, const Scaffold(body: SmartServicesInstances()),
        dark: false);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    Finder rowOf(String name) =>
        find.ancestor(of: find.text(name), matching: find.byType(ListTile));
    Finder spinnerIn(String name) => find.descendant(
        of: rowOf(name), matching: find.byType(DelayedCircularProgressIndicator));
    Finder upgradeIn(String name) =>
        find.descendant(of: rowOf(name), matching: find.byIcon(Icons.upgrade));

    await tester.tap(upgradeIn("Instance B"));
    await tester.pump();
    expect(spinnerIn("Instance B"), findsOneWidget);

    // The backend now lists B first, and a refresh arrives mid-upgrade.
    backend.serveJson("GET", "$_repo/instances", 200,
        [_instanceJson("inst-b", "Instance B"), _instanceJson("inst-a", "Instance A")]);
    AppState().pushRefresh();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(spinnerIn("Instance B"), findsOneWidget,
        reason: "the upgrade of B is still running");
    expect(upgradeIn("Instance A"), findsOneWidget);

    releaseParameters.complete();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final puts = backend.requests
        .where((r) => r.method == "PUT")
        .map((r) => r.uri.path)
        .toList();
    expect(puts, ["$_repo/instances/inst-b/parameters"]);
    expect(upgradeIn("Instance B"), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });
}
