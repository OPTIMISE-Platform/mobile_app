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
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/widgets/shared/slice_position.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/detail_page.dart';
import 'package:mobile_app/widgets/tabs/shared/device_list_item.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(() async {
    resetAppStateForGolden();
    resetGoldenBackend();
    await Settings.setFavoriteDeviceIds({});
  });

  DeviceInstance device() => DeviceInstance(
        "device-1",
        "device-1-local",
        "Living room lamp",
        null,
        "device-type-1",
        false,
        "owner-1",
        "Living room lamp",
        DeviceConnectionStatus.online,
      );

  testWidgets("long-pressing the row toggles favourite, tapping it opens the detail page",
      (tester) async {
    // Empty backend: any request DetailPage's refresh makes gets a fast 404
    // instead of reaching for the real network.
    serveGoldenBackend(FakeBackend());
    await tester.runAsync(() => Settings.setAccount("test-account"));
    final d = device();

    await pumpGolden(
      tester,
      Scaffold(body: DeviceListItem(d, null, position: SlicePosition.only)),
      dark: false,
    );

    expect(d.favorite, isFalse);
    // Not a real tester.longPress(): confirmed (probed directly) that it hits
    // the same wall as a tap did before the star moved out of the row - the
    // gesture dispatch and the onLongPress callback it fires both run inside
    // TestWidgetsFlutterBinding's fake-async zone, so the callback's real
    // Hive write (Settings, through FavorizeButton.click()) starts there too.
    // Nothing afterward - not a longer fake pump, not a real delay wrapped in
    // runAsync - ever observes that write land: runAsync only lets *new*
    // real work started inside it progress, and the already-running write's
    // continuation is stuck in the fake zone's own microtask queue, which
    // only pump() drains, on fake time that never elapses for it. The one
    // working pattern is to start the real work inside runAsync from the
    // beginning, so here that means invoking the resolved callback (exactly
    // what the long press would fire) directly, instead of synthesizing the
    // gesture.
    final tile = tester.widget<ListTile>(find.byType(ListTile).first);
    await tester.runAsync(() async {
      final dynamic onLongPress = tile.onLongPress;
      final dynamic result = onLongPress();
      if (result is Future) await result;
    });
    await tester.pump();
    expect(d.favorite, isTrue);
    expect(Settings.getFavoriteDeviceIds(), contains("device-1"));

    // Not find.text(): the title now carries the favourite star inline
    // (a WidgetSpan) after the toggle above, so its flattened text no longer
    // matches the plain name exactly.
    await tester.tap(find.byType(ListTile).first);
    // Not pumpAndSettle: DetailPage's refresh can leave a progress indicator
    // animating (see golden_helper.dart's pumpGolden doc comment). Bounded
    // pumps instead, with an extra round: the pushed route's own
    // DelayedCircularProgressIndicator mounts fresh on the second pump, so
    // its 200ms delay only starts elapsing on a third.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(DetailPage), findsOneWidget);
  });
}
