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
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/models/location.dart';
import 'package:mobile_app/widgets/shared/slice_position.dart';
import 'package:mobile_app/widgets/tabs/shared/device_list_item.dart';

import 'golden_helper.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() {
    resetAppStateForGolden();
  });

  // A device instance with a long, wrapping name and an on/off state - the
  // on/off state produces a trailing toggle only while the device is
  // reachable, so [offline] picks between the "chip" and "toggle" shapes the
  // same fixture can take.
  DeviceInstance device({required bool offline}) {
    final d = DeviceInstance(
      "device-1",
      "device-1-local",
      "Kitchen ceiling light strip with dimmer and colour control",
      null,
      "device-type-1",
      false,
      "owner-1",
      "Kitchen ceiling light strip with dimmer and colour control",
      offline ? DeviceConnectionStatus.offline : DeviceConnectionStatus.online,
    );
    d.states.add(DeviceState(
      true,
      "service-1",
      "service-group-1",
      dotenv.env["FUNCTION_GET_ON_OFF_STATE"]!,
      "aspect-1",
      false,
      null,
      null,
      d.id,
      "path",
      "group",
    ));
    return d;
  }

  Future<void> pumpRow(WidgetTester tester, Widget row,
      {required double width, required double scale}) {
    return pumpGolden(
      tester,
      Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: row),
        ),
      ),
      dark: false,
      size: Size(width, 400),
    );
  }

  for (final width in [320.0, 360.0]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets("device row at ${width}dp, scale $scale: no overflow",
          (tester) async {
        // Offline: long name plus the location subtitle wrapped with the
        // "Offline" chip - the combination device_list_item.dart:210-217
        // overflowed at 320dp/2.0 before the subtitle became a Wrap.
        AppState()
            .locations
            .add(Location("location-1", "Kitchen", "", "", ["device-1"], []));

        final errors = <FlutterErrorDetails>[];
        final oldOnError = FlutterError.onError;
        FlutterError.onError = (d) => errors.add(d);

        await pumpRow(
            tester,
            DeviceListItem(device(offline: true), null, position: SlicePosition.only),
            width: width,
            scale: scale);
        await tester.pump(const Duration(milliseconds: 100));

        FlutterError.onError = oldOnError;
        expect(errors, isEmpty,
            reason: errors.map((e) => e.exceptionAsString()).join('\n'));
      });
    }

    testWidgets("device row at ${width}dp: title keeps at least half the row",
        (tester) async {
      // Online: the on/off state now shows its toggle in trailing instead of
      // the chip, so this is the case that used to also carry the favourite
      // star there - together the two ate most of the row's width.
      await pumpRow(
          tester,
          DeviceListItem(device(offline: false), null, position: SlicePosition.only),
          width: width,
          scale: 1.0);
      await tester.pump(const Duration(milliseconds: 100));

      final rowWidth = tester.getSize(find.byType(ListTile).first).width;
      final titleWidth =
          tester.getSize(find.byKey(const Key('deviceListItemTitle'))).width;
      expect(titleWidth, greaterThanOrEqualTo(rowWidth * 0.5),
          reason: "title $titleWidth of row $rowWidth at ${width}dp");
    });
  }
}
