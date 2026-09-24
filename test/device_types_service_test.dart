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
import 'package:mobile_app/exceptions/unexpected_status_code_exception.dart';
import 'package:mobile_app/services/device_types.dart';

import 'fake_backend.dart';

void main() {
  late FakeBackend backend;

  setUp(() {
    backend = FakeBackend();
    serveDeviceTypes(backend);
  });

  List<String> paths() => backend.requests.map((r) => r.uri.path).toList();

  test("loads the user's device types, not the platform list", () async {
    backend.types["/device-repository/user-device-types"] = [deviceTypeJson("a")];
    backend.types["/device-repository/device-types"] = [deviceTypeJson("a"), deviceTypeJson("b")];

    final result = await DeviceTypesService.getDeviceTypes(null, Duration.zero);

    expect(result.map((t) => t.id), ["a"]);
    expect(paths(), ["/device-repository/user-device-types"]);
    expect(backend.requests.single.headers["authorization"], "Bearer t");
    expect(backend.requests.single.uri.queryParameters,
        {"limit": "9999", "offset": "0"});
  });

  for (final code in [404, 403]) {
    test("falls back to the platform list on $code", () async {
      backend.status["/device-repository/user-device-types"] = code;
      backend.types["/device-repository/device-types"] = [deviceTypeJson("a"), deviceTypeJson("b")];

      final result =
          await DeviceTypesService.getDeviceTypes(null, Duration.zero);

      expect(result.map((t) => t.id), ["a", "b"]);
      expect(paths(), [
        "/device-repository/user-device-types",
        "/device-repository/device-types",
      ]);
    });
  }

  test("does not fall back on a server error", () async {
    backend.status["/device-repository/user-device-types"] = 500;

    await expectLater(
        DeviceTypesService.getDeviceTypes(null, Duration.zero),
        throwsA(isA<UnexpectedStatusCodeException>()
            .having((e) => e.code, "code", 500)));
    expect(paths(), ["/device-repository/user-device-types"]);
  });

  test("pages through a list longer than one page", () async {
    backend.types["/device-repository/user-device-types"] =
        List.generate(10000, (i) => deviceTypeJson("t$i"));

    final result = await DeviceTypesService.getDeviceTypes(null, Duration.zero);

    expect(result, hasLength(10000));
    expect(backend.requests.map((r) => r.uri.queryParameters["offset"]),
        ["0", "9999"]);
  });

  test("specific ids go to the platform list", () async {
    backend.types["/device-repository/device-types"] = [deviceTypeJson("x")];

    final result = await DeviceTypesService.getDeviceTypes(["x", "y"]);

    expect(result.map((t) => t.id), ["x"]);
    expect(paths(), ["/device-repository/device-types"]);
    expect(backend.requests.single.uri.queryParameters["ids"], "x,y");
  });
}
