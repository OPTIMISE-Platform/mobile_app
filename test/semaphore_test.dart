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

import "dart:async";

import "package:flutter_test/flutter_test.dart";
import "package:mobile_app/shared/semaphore.dart";

void main() {
  group("Semaphore", () {
    test("bounds concurrency to maxConcurrent", () async {
      final semaphore = Semaphore(2);
      var running = 0;
      var peak = 0;

      Future<void> job() => semaphore.withResource(() async {
            running++;
            peak = peak > running ? peak : running;
            await Future<void>.delayed(const Duration(milliseconds: 5));
            running--;
          });

      await Future.wait([for (var i = 0; i < 6; i++) job()]);
      expect(peak, 2);
      expect(running, 0);
    });

    test("waiters are served in FIFO order", () async {
      final semaphore = Semaphore(1);
      final order = <int>[];

      await semaphore.acquire();
      final waiters = [
        for (var i = 0; i < 3; i++)
          semaphore.acquire().then((_) {
            order.add(i);
            semaphore.release();
          })
      ];
      semaphore.release();
      await Future.wait(waiters);

      expect(order, [0, 1, 2]);
    });

    test("withResource releases the permit when the action throws", () async {
      final semaphore = Semaphore(1);

      await expectLater(
          semaphore.withResource(() async => throw StateError("boom")),
          throwsStateError);

      // The permit must be available again: acquire resolves immediately.
      var acquired = false;
      unawaited(semaphore.acquire().then((_) => acquired = true));
      await Future<void>.delayed(Duration.zero);
      expect(acquired, isTrue);
    });
  });
}
