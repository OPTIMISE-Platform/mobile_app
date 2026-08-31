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

import "package:flutter_test/flutter_test.dart";
import "package:mobile_app/shared/chunked_parse.dart";

void main() {
  group("parseListChunked", () {
    test("parses every item in order across chunk boundaries", () async {
      final raw = [for (var i = 0; i < 1001; i++) {"v": i}];

      final parsed = await parseListChunked(raw, (json) => json["v"] as int);

      expect(parsed, hasLength(1001));
      expect(parsed.first, 0);
      expect(parsed[250], 250);
      expect(parsed.last, 1000);
    });

    test("handles an empty list", () async {
      expect(await parseListChunked([], (json) => json), isEmpty);
    });

    test("respects a custom chunk size", () async {
      final raw = [for (var i = 0; i < 10; i++) {"v": i}];
      final parsed =
          await parseListChunked(raw, (json) => json["v"] as int, chunkSize: 2);
      expect(parsed, [for (var i = 0; i < 10; i++) i]);
    });
  });
}
