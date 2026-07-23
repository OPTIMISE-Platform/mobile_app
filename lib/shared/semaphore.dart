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

import 'dart:async';

/// A simple counting semaphore that bounds how many async operations run at
/// once. [acquire] resolves immediately while permits are available, otherwise
/// it queues (FIFO) until another holder calls [release].
class Semaphore {
  Semaphore(this.maxConcurrent)
      : assert(maxConcurrent > 0),
        _available = maxConcurrent;

  final int maxConcurrent;
  int _available;
  final _waiters = <Completer<void>>[];

  Future<void> acquire() {
    if (_available > 0) {
      _available--;
      return Future.value();
    }
    final completer = Completer<void>();
    _waiters.add(completer);
    return completer.future;
  }

  void release() {
    if (_waiters.isNotEmpty) {
      // Hand the permit straight to the next waiter without touching the
      // counter — the waiter takes over this holder's permit.
      _waiters.removeAt(0).complete();
    } else {
      _available++;
    }
  }

  /// Runs [action] while holding a permit, releasing it even if [action]
  /// throws. Rethrows whatever [action] throws.
  Future<T> withResource<T>(Future<T> Function() action) async {
    await acquire();
    try {
      return await action();
    } finally {
      release();
    }
  }
}

/// Bounds concurrent device image downloads (device classes, groups, locations)
/// which all hit the same image host. Loading them all in parallel on a cold
/// cache triggers HTTP 429 (rate limiting).
final Semaphore imageDownloadLimiter = Semaphore(4);
