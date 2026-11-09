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
import 'package:mobile_app/live/live_values.dart';
import 'package:mobile_app/live/raw_value_source.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/pv_flow.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/shared/request.dart';

import 'golden_helper.dart';

Map<String, dynamic> request(String column) => {
      'method': 'GET',
      'url': 'https://api.senergy.infai.org/db/v3/raw-value?device_id=dev-$column&service_id=svc&column=$column&not_null=true',
      'body': null,
      'need_token': true,
    };

/// Records what the widget watches and hands the callbacks to the test.
class RecordingLive extends LiveValues {
  final sources = <RawValueSource>[];
  final callbacks = <void Function(dynamic, DateTime)>[];
  int released = 0;

  RecordingLive() : super();

  @override
  LiveHandle watchRaw(RawValueSource source, void Function(dynamic value, DateTime time) onValue) {
    sources.add(source);
    callbacks.add(onValue);
    return LiveHandle.forTest(() => released++);
  }
}

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  Future<SmSePvFlow> flow() async {
    final w = SmSePvFlow();
    await w.configure({
      'chargingViaInverter': false,
      'solarGenerationRequest': request('solar'),
      'chargePowerRequest': request('charge'),
      'dischargePowerRequest': request('discharge'),
      'gridConsumptionRequests': [request('grid1'), request('grid2')],
      'batteryLevelRequest': request('battery'),
    });
    return w;
  }

  group('flow from last values', () {
    test('a live value for the solar request changes the computed flow', () async {
      final w = await flow();
      w.setRequestValue(w.gridConsumptionRequests[0], -1000);
      w.setRequestValue(w.gridConsumptionRequests[1], -500);
      w.setRequestValue(w.solarGenerationRequest!, 3000);
      expect(w.flows['solar'], 3000);
      expect(w.flows['grid'], -1500);
      expect(w.flows['household'], 1500, reason: 'grid + solar');
      expect(w.flows['solarToGrid'], 1500);

      w.setRequestValue(w.solarGenerationRequest!, 4000);
      expect(w.flows['solar'], 4000);
      expect(w.flows['household'], 2500);
      expect(w.flows['solarToGrid'], 1500);
    });

    test('the grid requests are summed and a positive sum is drawn from the grid', () async {
      final w = await flow();
      w.setRequestValue(w.solarGenerationRequest!, 1000);
      w.setRequestValue(w.gridConsumptionRequests[0], 300);
      w.setRequestValue(w.gridConsumptionRequests[1], 200);
      expect(w.flows['grid'], 500);
      expect(w.flows['gridToHousehold'], 500);
      expect(w.flows['solarToHousehold'], 1000);
      expect(w.flows['household'], 1500);
    });

    test('a negative charge power is a discharge', () async {
      final w = await flow();
      w.setRequestValue(w.chargePowerRequest!, -400);
      expect(w.flows['batteryToHousehold'], 400);
      expect(w.flows['householdToBattery'], isNull);
    });

    test('a request that is not the widget\'s changes nothing', () async {
      final w = await flow();
      w.setRequestValue(w.solarGenerationRequest!, 100);
      final before = Map.of(w.flows);
      w.setRequestValue(Request.from(w.solarGenerationRequest!), 9999);
      expect(w.flows, before);
    });
  });

  group('live watches of the widget', () {
    testWidgets('watches every raw-value request, applies a value and releases on dispose', (tester) async {
      final w = await flow();
      final live = RecordingLive();
      w.live = live;

      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) => w.buildInternal(c, false)))));
      expect(live.sources.map((s) => s.column), ['solar', 'charge', 'discharge', 'grid1', 'grid2', 'battery']);
      expect(live.sources.first.deviceId, 'dev-solar');

      live.callbacks[0](2500, DateTime.now());
      expect(w.flows['solar'], 2500);
      live.callbacks[0]('not a number', DateTime.now());
      live.callbacks[0](true, DateTime.now());
      live.callbacks[0](double.nan, DateTime.now());
      expect(w.flows['solar'], 2500);
      live.callbacks[0]('1800.5', DateTime.now());
      expect(w.flows['solar'], 1800.5);

      // The ticker rebuilds the painters every frame.
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      expect(live.released, 6);
    });

    testWidgets('in preview mode nothing is watched, other URLs are skipped', (tester) async {
      final w = SmSePvFlow();
      await w.configure({
        'solarGenerationRequest': request('solar'),
        'chargePowerRequest': {'method': 'GET', 'url': 'https://x.test/other', 'body': null, 'need_token': false},
      });
      final live = RecordingLive();
      w.live = live;
      w.setPreview(true);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) => w.buildInternal(c, false)))));
      expect(live.sources, isEmpty);
      await tester.pumpWidget(const SizedBox());

      final w2 = SmSePvFlow();
      await w2.configure({
        'solarGenerationRequest': request('solar'),
        'chargePowerRequest': {'method': 'GET', 'url': 'https://x.test/other', 'body': null, 'need_token': false},
      });
      final live2 = RecordingLive();
      w2.live = live2;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(builder: (c) => w2.buildInternal(c, false)))));
      expect(live2.sources.map((s) => s.column), ['solar']);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
