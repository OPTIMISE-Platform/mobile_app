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
import "package:mobile_app/widgets/shared/slice_position.dart";

void main() {
  group("SlicePosition.forIndex", () {
    test("a single row is only", () {
      expect(SlicePosition.forIndex(0, 1), SlicePosition.only);
    });

    test("the first row of several is first", () {
      expect(SlicePosition.forIndex(0, 3), SlicePosition.first);
    });

    test("a row between the first and last is middle", () {
      expect(SlicePosition.forIndex(1, 3), SlicePosition.middle);
    });

    test("the last row of several is last", () {
      expect(SlicePosition.forIndex(2, 3), SlicePosition.last);
    });

    test("both rows of a two-row section are first and last, not only", () {
      expect(SlicePosition.forIndex(0, 2), SlicePosition.first);
      expect(SlicePosition.forIndex(1, 2), SlicePosition.last);
    });
  });
}
