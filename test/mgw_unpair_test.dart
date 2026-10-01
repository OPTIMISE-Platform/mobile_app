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

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/services/mgw/auth_service.dart';
import 'package:mobile_app/services/mgw/reachability.dart';
import 'package:mobile_app/services/mgw/storage.dart';
import 'package:mobile_app/widgets/tabs/gateways/unpair_dialog.dart';

import 'golden_helper.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
    await MgwStorage.init();
    // The constructor starts a discovery of its own; let it end first.
    AppState();
    await Future<void>.delayed(const Duration(milliseconds: 200));
  });

  tearDown(() async {
    MgwReachability.probeOverride = null;
    MgwReachability.forget();
    await MgwStorage.ReplacePairedMGWs([]);
    resetAppStateForGolden();
  });

  test("a failing update after removing a pairing is logged, not thrown",
      () async {
    final kitchen = MGW("a.local", "A", "c1", "10.0.0.1", networkId: "n1");
    final garage = MGW("b.local", "B", "c2", "10.0.0.2", networkId: "n2");
    await MgwStorage.ReplacePairedMGWs([kitchen, garage]);
    await MgwStorage.StoreCredentials(DeviceUserCredentials("id", "l", "s"));
    // The merge after the removal probes the remaining gateway.
    MgwReachability.probeOverride =
        (host, expect) async => throw StateError("probe broke");

    expect(await removeConfirmedPairing(kitchen), PairingRemoval.removed);
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect((await MgwStorage.LoadPairedMGWs()).single.hostname, "b.local");
  });

  test("a pairing that is no longer stored is reported, not removed",
      () async {
    await MgwStorage.ReplacePairedMGWs(
        [MGW("b.local", "B", "c2", "10.0.0.2", networkId: "n2")]);

    final result = await removeConfirmedPairing(
        MGW("a.local", "A", "c1", "10.0.0.1", networkId: "n1"));

    expect(result, PairingRemoval.notFound);
    expect(await MgwStorage.LoadPairedMGWs(), hasLength(1));
  });
}
