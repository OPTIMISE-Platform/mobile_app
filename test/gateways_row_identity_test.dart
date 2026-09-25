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
      "reordering gateways that share an empty coreId keeps each row's "
      "status dot state with its own host", (tester) async {
    // Both manually paired (see mgw_page.dart's _addManually), which always
    // stores coreId "" - the case a coreId key collides on.
    final gatewayA = MGW("host-a", "Gateway A", "", "10.0.0.1");
    final gatewayB = MGW("host-b", "Gateway B", "", "10.0.0.2");
    AppState().gateways.addAll([gatewayA, gatewayB]);

    await pumpGolden(tester, const Scaffold(body: Gateways()), dark: false);

    State<MgwStatusDot> stateFor(String host) => tester.state(
        find.byWidgetPredicate((w) => w is MgwStatusDot && w.host == host));

    // MgwStatusDot is given mgw.ip, not mgw.hostname, as its own "host".
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
            "host-a's status dot state should follow host-a, not swap with "
            "whatever row is now at host-a's old position");
    expect(identical(beforeB, afterB), isTrue,
        reason:
            "host-b's status dot state should follow host-b, not swap with "
            "whatever row is now at host-b's old position");
  });
}
