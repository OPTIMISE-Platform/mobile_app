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

import 'package:mobile_app/shared/account_epoch.dart';

/// Lets concurrent calls of a loader share one run, and its outcome.
///
/// A caller arriving while a run is in flight gets that run's result, not an
/// assumed success: the settings refresh reported "Cache refreshed" over a
/// joined load that had failed. Only a run started under the current
/// [AccountEpoch] is joined; a call after an account change starts its own.
class JoinedLoad {
  Future<bool>? _running;
  int? _runningEpoch;

  Future<bool> run(Future<bool> Function() load) {
    final epoch = AccountEpoch.current;
    final running = _running;
    if (running != null && _runningEpoch == epoch) return running;
    late final Future<bool> started;
    // Cleared only by its own run: an older run ending must not drop a newer
    // one that later callers should still join.
    started = load().whenComplete(() {
      if (identical(_running, started)) {
        _running = null;
        _runningEpoch = null;
      }
    });
    _running = started;
    _runningEpoch = epoch;
    return started;
  }
}
