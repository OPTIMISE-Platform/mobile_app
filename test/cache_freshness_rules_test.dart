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
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/shared/metadata_cache.dart';

void main() {
  final now = DateTime.utc(2026, 3, 29, 12);

  group("metadata", () {
    test("is current up to exactly maxAge and stale one microsecond later", () {
      expect(MetadataCache.isStale(now.subtract(metadataMaxAge), metadataMaxAge, now),
          isFalse);
      expect(
          MetadataCache.isStale(
              now.subtract(metadataMaxAge + const Duration(microseconds: 1)),
              metadataMaxAge,
              now),
          isTrue);
    });

    test("stored in the future counts as stale", () {
      expect(
          MetadataCache.isStale(
              now.add(const Duration(microseconds: 1)), metadataMaxAge, now),
          isTrue);
    });
  });

  group("entities", () {
    test("never refreshed is due", () {
      expect(CacheHelper.entityRefreshDue(null, now), isTrue);
    });

    test("due from exactly one day on, as the old timer fired then", () {
      final justUnder = now.subtract(
          CacheHelper.entityMaxAge - const Duration(microseconds: 1));
      expect(CacheHelper.entityRefreshDue(justUnder, now), isFalse);
      expect(CacheHelper.entityRefreshDue(
          now.subtract(CacheHelper.entityMaxAge), now), isTrue);
    });

    test("refreshed in the future is due rather than waited for", () {
      expect(CacheHelper.entityRefreshDue(
          now.add(const Duration(days: 3)), now), isTrue);
    });
  });
}
