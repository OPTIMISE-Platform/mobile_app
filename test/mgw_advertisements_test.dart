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

void main() {
  group("networkIdFrom", () {
    test("reads the id the cloud proxy advertises", () {
      // Shape recorded from a running gateway.
      final body = [
        {
          "id": "01a0b3b1-8dd9-7db4-b980-f968df6f0bfd",
          "module_id": "github.com/SENERGY-Platform/mgw-cloud-proxy/mgw-module",
          "reference": "network",
          "items": {"id": "urn:infai:ses:hub:8e6c47e1"}
        }
      ];
      expect(MgwAdvertisements.networkIdFrom(body),
          equals("urn:infai:ses:hub:8e6c47e1"));
    });

    test("ignores advertisements under another reference", () {
      final body = [
        {
          "reference": "something-else",
          "items": {"id": "urn:infai:ses:hub:wrong"}
        }
      ];
      expect(MgwAdvertisements.networkIdFrom(body), equals(""));
    });

    test("is empty when the gateway advertises nothing", () {
      // A gateway whose cloud proxy is not signed in answers with an empty
      // list - that is an empty answer, not an error.
      expect(MgwAdvertisements.networkIdFrom([]), equals(""));
    });

    test("survives a body that is not the expected shape", () {
      expect(MgwAdvertisements.networkIdFrom(null), equals(""));
      expect(MgwAdvertisements.networkIdFrom({"reference": "network"}),
          equals(""));
      expect(
          MgwAdvertisements.networkIdFrom([
            {"reference": "network"}
          ]),
          equals(""));
      expect(
          MgwAdvertisements.networkIdFrom([
            {"reference": "network", "items": {"id": ""}}
          ]),
          equals(""));
    });

    test("skips an empty id instead of settling for it", () {
      // Returning the empty value would end the search, and the usable entry
      // behind it would never be seen.
      final body = [
        {"reference": "network", "items": {"id": ""}},
        {"reference": "network", "items": {"id": "urn:infai:ses:hub:real"}}
      ];
      expect(MgwAdvertisements.networkIdFrom(body),
          equals("urn:infai:ses:hub:real"));
    });
  });
}
