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
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/widgets/tabs/gateways/gateways.dart';
import 'package:mobile_app/widgets/tabs/gateways/mgw_status_dot.dart';

import 'golden_helper.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
  });

  testWidgets(
      "reordering gateways that share an empty coreId and a hostname keeps "
      "each row's status dot state with its own entry", (tester) async {
    // Both added by address (see mgw_page.dart's _addManually), which stores
    // coreId "", under the same hostname bound to two networks - the case a
    // coreId or hostname key collides on.
    final gatewayA = MGW("mgw.local", "Gateway A", "", "10.0.0.1",
        networkId: "n1", pairingId: "pairing-a");
    final gatewayB = MGW("mgw.local", "Gateway B", "", "10.0.0.2",
        networkId: "n2", pairingId: "pairing-b");
    AppState().gateways.addAll([gatewayA, gatewayB]);

    await pumpGolden(tester, const Scaffold(body: Gateways()), dark: false);

    State<MgwStatusDot> stateFor(String host) => tester.state(
        find.byWidgetPredicate((w) => w is MgwStatusDot && w.gateway.ip == host));

    // Found by the entry's ip, not its hostname.
    final beforeA = stateFor("10.0.0.1");
    final beforeB = stateFor("10.0.0.2");

    // Reordered, not added or removed - e.g. what a re-sorted refresh would
    // produce - so the only question is whether each row's own State follows
    // its host or stays pinned to its old position.
    AppState().gateways.setAll(0, [gatewayB, gatewayA]);
    AppState().notifyListeners();
    await tester.pump();

    final afterA = stateFor("10.0.0.1");
    final afterB = stateFor("10.0.0.2");

    expect(identical(beforeA, afterA), isTrue,
        reason:
            "A's status dot state should follow A, not swap with "
            "whatever row is now at A's old position");
    expect(identical(beforeB, afterB), isTrue,
        reason:
            "B's status dot state should follow B, not swap with "
            "whatever row is now at B's old position");
  });
}
