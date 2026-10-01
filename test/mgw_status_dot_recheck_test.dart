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
import 'package:mobile_app/services/mgw/reachability.dart';
import 'package:mobile_app/widgets/tabs/gateways/mgw_status_dot.dart';

void main() {
  var status = MgwStatus.unauthorized;
  var probes = 0;

  setUp(() {
    status = MgwStatus.unauthorized;
    probes = 0;
    MgwReachability.forget();
    MgwReachability.probeOverride = (host, expect) async {
      probes++;
      return MgwReport(
          status: status, address: host, checkedAt: DateTime.utc(2026));
    };
  });

  tearDown(() {
    MgwReachability.probeOverride = null;
    MgwReachability.forget();
  });

  // A dot left mounted would still listen when the next setUp drops the cache.
  Future<void> unmount(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  Color dotColor(WidgetTester tester) =>
      tester.widget<Icon>(find.byIcon(Icons.fiber_manual_record)).color!;

  Future<void> pumpDot(WidgetTester tester, {Key? key}) => tester.pumpWidget(
      MaterialApp(
          home: Center(
              child: MgwStatusDot(
                  key: key, host: "10.0.0.1", expectNetworkId: "n1"))));

  testWidgets("a failed check is checked again once the cache is dropped",
      (tester) async {
    await pumpDot(tester);
    await tester.pump();
    expect(dotColor(tester), MgwStatusDot.colorOf(MgwStatus.unauthorized));

    // The gateway accepts the phone again, e.g. after pairing again; the
    // failed answer is still cached and the dot built its future long ago.
    status = MgwStatus.ok;
    MgwReachability.forget();
    await tester.pump();
    await tester.pump();

    expect(dotColor(tester), MgwStatusDot.colorOf(MgwStatus.ok));
    expect(probes, 2);
    await unmount(tester);
  });

  testWidgets("a status found by another check reaches the dot",
      (tester) async {
    await pumpDot(tester);
    await tester.pump();
    expect(dotColor(tester), MgwStatusDot.colorOf(MgwStatus.unauthorized));

    status = MgwStatus.ok;
    // "Check again" in the status sheet: a forced probe of the same gateway.
    final forced =
        MgwReachability.check("10.0.0.1", expectNetworkId: "n1", force: true);
    await tester.pump();
    await tester.pump();

    expect((await forced).status, MgwStatus.ok);
    expect(dotColor(tester), MgwStatusDot.colorOf(MgwStatus.ok));
    await unmount(tester);
  });

  testWidgets("rebuilding the dot does not probe again", (tester) async {
    await pumpDot(tester);
    await tester.pump();
    expect(probes, 1);

    for (var i = 0; i < 3; i++) {
      await pumpDot(tester);
      await tester.pump();
    }

    expect(probes, 1);
    await unmount(tester);
  });
}
