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
import 'package:mobile_app/config/functions/function_config.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/tabs/sensors/sensor_sparkline.dart';
import 'package:mobile_app/widgets/tabs/sensors/switch_tile.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/shared/account_epoch.dart';
import 'package:mobile_app/widgets/tabs/sensors/switch_commands.dart';

import 'golden_helper.dart';
import 'sensor_switch_fixture.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  group('onOffReadingOf', () {
    test('reads a device value', () {
      expect(onOffReadingOf(true), OnOffReading.on);
      expect(onOffReadingOf(false), OnOffReading.off);
      expect(onOffReadingOf(null), OnOffReading.unknown);
      expect(onOffReadingOf('on'), OnOffReading.unknown);
      expect(onOffReadingOf(1), OnOffReading.unknown);
    });

    test('reads a group value by the members that answered', () {
      expect(onOffReadingOf([true, true]), OnOffReading.on);
      expect(onOffReadingOf([false]), OnOffReading.off);
      expect(onOffReadingOf([true, false]), OnOffReading.mixed);
      expect(onOffReadingOf([true, false, null]), OnOffReading.mixed);
      expect(onOffReadingOf([true, null]), OnOffReading.on,
          reason: 'an unreachable member must not keep the rest from going off');
      expect(onOffReadingOf([false, null]), OnOffReading.off);
      expect(onOffReadingOf(<dynamic>[]), OnOffReading.unknown);
      expect(onOffReadingOf([null, null]), OnOffReading.unknown);
      expect(onOffReadingOf([true, 'x']), OnOffReading.unknown);
    });
  });

  group('isSwitchableOnOff', () {
    // The Shelly 1PM Gen4 reads its relay and its button input with the same
    // binary-state function; only the relay has a control.
    DeviceState state(String function, bool controlling, List<String> aspects, {String? groupId}) =>
        DeviceState(null, 'svc', 'group-1', function, null, controlling, groupId, null,
            groupId == null ? 'shelly' : null, 'path', null,
            aspectIds: aspects);
    // Built per test: the function ids come from the environment set up above.
    List<DeviceState> shelly() => [
          state(onOffFunction, false, ['device']),
          state(onOffFunction, false, ['button']),
          state(setOnFunction, true, ['device']),
          state(setOffFunction, true, ['device']),
        ];

    test('a reading with a control on its aspect is a switch', () {
      final device = shelly();
      expect(isSwitchableOnOff(device[0], device), isTrue);
    });

    test('a reading no control pairs with is none', () {
      final device = shelly();
      expect(isSwitchableOnOff(device[1], device), isFalse);
      expect(isSwitchableOnOff(device[0], [device[0]]), isFalse);
    });

    test('a control is no switch reading itself', () {
      final device = shelly();
      expect(isSwitchableOnOff(device[2], device), isFalse);
    });

    test('a group pairs with any control, since its criteria carry no aspect', () {
      final reading = state(onOffFunction, false, [], groupId: 'g');
      expect(isSwitchableOnOff(reading, [reading, state(setOnFunction, true, [], groupId: 'g')], isGroup: true),
          isTrue);
      expect(isSwitchableOnOff(reading, [reading], isGroup: true), isFalse);
    });
  });

  test('a toggle switches off what is on, and on what is off or mixed', () {
    expect(onOffTargetFunction(OnOffReading.on), setOffFunction);
    expect(onOffTargetFunction(OnOffReading.off), setOnFunction);
    expect(onOffTargetFunction(OnOffReading.mixed), setOnFunction);
    expect(onOffTargetFunction(OnOffReading.unknown), isNull,
        reason: 'the config guesses "on" for an unknown value');
    // The config agrees for every value the tile switches.
    final config = functionConfigs[onOffFunction]!;
    for (final value in [
      true,
      false,
      [true, true],
      [false, false],
      [true, false],
      [true, null],
      [false, null],
      [true, false, null],
    ]) {
      expect(onOffTargetFunction(onOffReadingOf(value)),
          config.getRelatedControllingFunction(value),
          reason: '$value');
    }
  });

  test('a read-back of a previous account is not put back', () async {
    DeviceState reading() => DeviceState(null, 'svc-get', 'group-1',
        onOffFunction, null, false, null, null, 'fan', 'on', null,
        aspectIds: const ['power']);
    addTearDown(SwitchCommands.resetForTest);
    final measurement = reading();
    final loadStartedAt = SwitchCommands.beginLoad();
    await SwitchCommands.run(measurement, () async {
      measurement.value = true;
      return true;
    });

    final sameAccount = reading()..value = false;
    expect(SwitchCommands.reapply([sameAccount], loadStartedAt), isTrue);
    expect(sameAccount.value, isTrue);

    AccountEpoch.advance();
    final nextAccount = reading()..value = false;
    expect(SwitchCommands.reapply([nextAccount], loadStartedAt), isFalse);
    expect(nextAccount.value, isFalse);
  });

  testWidgets('a group with unanswered members shows what the others report',
      (tester) async {
    late BuildContext context;
    await tester.pumpWidget(Builder(builder: (c) {
      context = c;
      return const SizedBox();
    }));
    final config = functionConfigs[onOffFunction]!;
    IconData? iconOf(dynamic value) =>
        (config.displayValue(value, context) as Icon?)?.icon;
    expect(iconOf([true, null]), iconOf(true));
    expect(iconOf([false, null]), iconOf(false));
    expect(iconOf([true, false, null]), Icons.remove);
    expect(iconOf([null, null]), isNull);
    expect(iconOf(<dynamic>[]), isNull);
  });

  test('an on/off reading draws no sparkline', () {
    DeviceState reading(String functionId) => DeviceState(null, 'svc-get',
        'group-1', functionId, null, false, null, null, 'fan', 'on', null,
        aspectIds: const ['power']);
    expect(canShowSparkline(reading(onOffFunction)), isFalse);
    expect(canShowSparkline(reading('urn:infai:ses:measuring-function:temp')),
        isTrue);
  });

  for (final dark in [false, true]) {
    test('a tile that is on keeps its contrast (${dark ? 'dark' : 'light'})',
        () {
      final theme = dark ? MyTheme.materialDarkTheme : MyTheme.materialTheme;
      final card = switchTileOnColor(theme);
      expect(card, isNot(theme.cardTheme.color), reason: 'the tile is tinted');
      final text = <String, Color>{
        'title': theme.textTheme.bodyMedium!.color!,
        'subtitle': theme.textTheme.bodySmall!.color!,
        'label': theme.textTheme.titleMedium!.color!,
      };
      for (final entry in text.entries) {
        expect(_contrast(entry.value, card), greaterThanOrEqualTo(4.5),
            reason: '${entry.key} on the tinted card');
      }
      // Material's switch paints its on track in primary.
      expect(_contrast(theme.colorScheme.primary, card),
          greaterThanOrEqualTo(3),
          reason: 'switch track on the tinted card');
    });
  }
}
