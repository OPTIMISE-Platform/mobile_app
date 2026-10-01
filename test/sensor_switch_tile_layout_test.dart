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
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';
import 'sensor_switch_fixture.dart';

const _longTitle = 'Bathroom ceiling fan above the shower cabin';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  /// The lines [text] is laid out in.
  int linesOf(WidgetTester tester, String text) {
    final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
    final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: text.length));
    return boxes.map((b) => b.top.round()).toSet().length;
  }

  // One testWidgets for every combination, see sensor_values_overflow_test.
  testWidgets('switch tiles fit at every phone width and text scale',
      (tester) async {
    for (final width in [320.0, 360.0, 412.0]) {
      for (final scale in [1.0, 1.3, 1.5, 2.0]) {
        final at = 'at ${width}dp, scale $scale';
        final backend = PlugBackend();
        backend.serveJson('GET', devicesPath, 200, [
          deviceJson('fan', 'Bathroom fan', deviceTypeId: 'plug'),
          deviceJson('pump', 'Garden pump', deviceTypeId: 'plug'),
          deviceJson('heater', 'Heater in the basement storage room',
              deviceTypeId: 'plug', connectionState: 'offline'),
        ]);
        backend.values['fan'] = true;
        serveGoldenBackend(backend);
        await warmUpMgwStorage(tester);
        AppState().deviceTypes['plug'] = plugType('plug');
        registerOnOffFunctions();

        final errors = <FlutterErrorDetails>[];
        final oldOnError = FlutterError.onError;
        FlutterError.onError = (d) => errors.add(d);
        await mountSensorPage(
          tester,
          [
            plugPin('fan', _longTitle),
            plugPin('pump', 'Pump'),
            plugPin('heater', 'Heater power'),
          ],
          size: Size(width, 800),
          textScale: scale,
        );
        FlutterError.onError = oldOnError;
        expect(errors, isEmpty,
            reason: '$at:\n'
                '${errors.map((e) => e.exceptionAsString()).join('\n')}');

        expect(labelOf(tester, _longTitle), 'On', reason: at);
        expect(labelOf(tester, 'Pump'), 'Unknown', reason: at);
        expect(labelOf(tester, 'Heater power'), 'Offline', reason: at);
        expect(linesOf(tester, _longTitle), 2,
            reason: '$at: a long title keeps its second line');
        for (final alias in [_longTitle, 'Pump', 'Heater power']) {
          final card = tester.getRect(cardOf(alias));
          final toggle = tester.getRect(inCard(alias, find.byType(Switch)));
          expect(card.contains(toggle.topLeft) && card.contains(toggle.bottomRight),
              isTrue,
              reason: '$at: the switch of "$alias" lies inside its card');
        }

        resetAppStateForGolden();
        resetGoldenBackend();
      }
    }
  });
}
