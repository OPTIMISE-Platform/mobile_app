/*
 * Copyright (c) 2026 InfAI (CC SES)
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

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/base.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/shared/widget_info.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

// refresh() of the ventilation widget against a fake backend, and the height
// it reports for the dashboard. Plain tests, not testWidgets: each one makes a
// request, which a second testWidgets in a file would not get answered
// (docs/testing.md).
void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  late FakeBackend backend;
  setUp(() {
    backend = FakeBackend();
    serveGoldenBackend(backend);
  });

  tearDown(() {
    resetGoldenBackend();
  });

  const path = "/widget-data/ventilation";

  Future<SmartServiceModuleWidget> refreshed() async {
    final w = (await SmartServiceModuleWidget.fromWidgetInfo(
        "ventilation",
        WidgetInfo.fromJson({
          "widget_type": smSeVentilationType,
          "widget_data": {
            "request": {"method": "GET", "url": "https://api.test$path", "body": null, "need_token": false},
          },
        })))!;
    await w.refresh();
    return w;
  }

  Map<String, dynamic> envelope(int rooms) => {
        "key": "dep-1_ventilation_state",
        "updated_at": "2026-10-23T07:59:12.123Z",
        "value": {
          "outdoor": {"t": 8.1, "rh": 90.0, "valid": true},
          "rooms": [
            for (var i = 0; i < rooms; i++)
              {"name": "Raum $i", "state": "helps", "t": 21.0, "rh": 70.0, "rh_after": 50.0},
          ],
        },
      };

  // padding 2 x 12, header 24 + 4 + 20 + 12, rows of 48 with 1 px between,
  // rounded up to units of 32 px
  test("the height grows with the rooms", () async {
    for (final (rooms, units) in [(0, 3.0), (1, 5.0), (4, 9.0), (10, 18.0)]) {
      backend.serveJson("GET", path, 200, envelope(rooms));
      expect((await refreshed()).height, units, reason: "$rooms rooms");
    }
  });

  test("a 404 shows no data", () async {
    backend.serveJson("GET", path, 404, {"kind": "not_found", "message": "key not found"});
    expect((await refreshed()).height, 3);
  });

  test("a body that is not JSON shows no data", () async {
    backend.serveJson("GET", path, 200, "not json", contentType: "text/plain");
    expect((await refreshed()).height, 3);
  });

  test("a failed connection shows no data and does not throw", () async {
    backend.failures["GET $path"] = DioExceptionType.connectionError;
    expect((await refreshed()).height, 3);
  });
}
