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

import 'package:flutter/foundation.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/shared/account_epoch.dart';

/// A switch command that ended, with the value it read back if it did.
class SwitchCommandEnd {
  final String _key;
  final DeviceState measurement;

  /// Whether it read a value back for the account still signed in.
  final bool readBack;

  const SwitchCommandEnd._(this._key, this.measurement, this.readBack);

  /// Whether [state] is the one the command switched, maybe another object of
  /// it from another load.
  bool isFor(DeviceState state) => SwitchCommands._keyOf(state) == _key;
}

/// The switch tiles' commands in flight and the values they read back, kept
/// outside the page so that leaving it, a remount or a reload loses neither.
///
/// A state is identified by what stays the same across reloads, not by its
/// object, which every device load replaces.
abstract final class SwitchCommands {
  /// Counts command ends and load starts, so they can be ordered.
  static int _sequence = 0;

  static final Set<String> _running = {};

  static final Map<String, ({int finishedAt, Object? value, int epoch})>
  _readBacks = {};

  static final StreamController<SwitchCommandEnd> _ended =
      StreamController.broadcast(sync: true);

  /// Every command that ends, once.
  static Stream<SwitchCommandEnd> get ended => _ended.stream;

  static String _keyOf(DeviceState state) => [
    state.deviceId ?? '',
    state.groupId ?? '',
    state.deviceClassId ?? '',
    state.functionId,
    state.serviceGroupKey ?? '',
    state.aspectKey,
  ].join('|');

  /// Whether a command for [state] is running.
  static bool isRunning(DeviceState state) => _running.contains(_keyOf(state));

  /// Marks the start of a load; pass the result to [reapply] once its values
  /// are in.
  static int beginLoad() => ++_sequence;

  /// Runs [toggle] of [measurement] unless a command for the same state is
  /// running, and keeps the value it read back. [toggle] returns whether it
  /// read the value back.
  static Future<void> run(
    DeviceState measurement,
    Future<bool> Function() toggle,
  ) async {
    final key = _keyOf(measurement);
    if (!_running.add(key)) return;
    final epoch = AccountEpoch.current;
    var readBack = false;
    try {
      readBack = await toggle() && epoch == AccountEpoch.current;
      if (readBack) {
        _readBacks[key] = (
          finishedAt: ++_sequence,
          value: measurement.value,
          epoch: epoch,
        );
      }
    } finally {
      _running.remove(key);
      _ended.add(SwitchCommandEnd._(key, measurement, readBack));
    }
  }

  /// Puts back on [states], right after the load started at [loadStartedAt]
  /// wrote them, the values read back by commands that finished after it
  /// started, which that load read too early. Returns whether a value changed.
  static bool reapply(Iterable<DeviceState> states, int loadStartedAt) {
    var changed = false;
    for (final state in states) {
      final key = _keyOf(state);
      final readBack = _readBacks[key];
      if (readBack == null) continue;
      if (readBack.finishedAt < loadStartedAt ||
          readBack.epoch != AccountEpoch.current) {
        // A load started since has read a newer value, or the account changed.
        _readBacks.remove(key);
        continue;
      }
      if (state.value != readBack.value) {
        state.value = readBack.value;
        changed = true;
      }
    }
    return changed;
  }

  @visibleForTesting
  static void resetForTest() {
    _running.clear();
    _readBacks.clear();
  }
}
