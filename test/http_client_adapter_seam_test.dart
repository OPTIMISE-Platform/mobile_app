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
import 'package:mobile_app/services/mgw/advertisements.dart';
import 'package:mobile_app/shared/http_client_adapter.dart';

import 'fake_backend.dart';

void main() {
  tearDown(() {
    AppHttpClientAdapter.testOverride = null;
  });

  test("testOverride reaches a Dio built outside DioFactory", () async {
    final backend = FakeBackend();
    backend.serveJson("GET", "/core/discovery", 200, [
      {
        "reference": MgwAdvertisements.networkReference,
        "items": {"id": "urn:infai:ses:hub:seam"}
      }
    ]);
    AppHttpClientAdapter.testOverride = backend;

    // TEST-NET-1 address: without the seam the request goes to the network
    // and networkIdOf swallows the failure as "".
    final id = await MgwAdvertisements.networkIdOf("192.0.2.10");

    expect(id, "urn:infai:ses:hub:seam");
    expect(backend.requests.single.uri.host, "192.0.2.10");
  });
}
