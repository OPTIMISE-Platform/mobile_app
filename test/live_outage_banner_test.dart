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
import 'package:mobile_app/live/live_values.dart';
import 'package:mobile_app/widgets/shared/app_bar.dart';

void main() {
  const platform = (routeKey: LiveValues.cloudRoute, gatewayName: null);
  LiveOutage gateway(String name) => (routeKey: 'gateway:$name', gatewayName: name);

  String? text(List<LiveOutage> outages, {bool platformUnreachable = false}) =>
      MyAppBar.liveOutageText(outages, platformUnreachable: platformUnreachable);

  test('names each source, several in one sentence', () {
    expect(text([]), isNull);
    expect(text([platform]), ' No live values from the platform');
    expect(text([gateway('Keller')]), ' No live values from Keller');
    expect(text([platform, gateway('Keller')]), ' No live values from the platform and Keller');
    expect(text([platform, gateway('Keller'), gateway('Garage')]),
        ' No live values from the platform, Keller and Garage');
  });

  test('leaves the platform out while the platform banner explains it', () {
    expect(text([platform], platformUnreachable: true), isNull);
    expect(text([platform, gateway('Keller')], platformUnreachable: true), ' No live values from Keller');
  });
}
