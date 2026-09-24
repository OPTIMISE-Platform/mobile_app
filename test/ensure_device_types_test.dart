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
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/mixins/device_mixin.dart';
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/shared/metadata_cache.dart';

class _State extends ChangeNotifier with DeviceMixin {
  _State(this.backend) {
    fetchDeviceTypes = (maxAge) async {
      fetches.add(maxAge);
      // What the backend held when the request went out.
      final ids = backend;
      final gate = this.gate;
      if (gate != null) await gate.future;
      if (fail) throw Exception("offline");
      return ids.map((id) => DeviceType(id, id, "", "", [], null)).toList();
    };
  }

  /// The type ids the backend currently returns.
  List<String> backend;
  final List<Duration> fetches = [];
  bool fail = false;

  /// While set, fetches wait for it to complete.
  Completer<void>? gate;

  @override
  Future<void> ensureInitialized() async {}
}

Future<_State> _loaded(List<String> backend) async {
  final s = _State(backend);
  await s.loadDeviceTypes();
  s.fetches.clear();
  return s;
}

void main() {
  test("a known type loads nothing", () async {
    final s = await _loaded(["a"]);
    await s.ensureDeviceTypes(["a"]);
    expect(s.fetches, isEmpty);
  });

  test("a missing type reloads the list once, bypassing the cache", () async {
    final s = await _loaded(["a"]);
    s.backend = ["a", "b"];
    await s.ensureDeviceTypes(["a", "b"]);
    expect(s.fetches, [Duration.zero]);
    expect(s.deviceTypes.keys, containsAll(["a", "b"]));
  });

  test("types the backend does not deliver are not refetched on later pages",
      () async {
    final s = await _loaded(["a"]);
    await s.ensureDeviceTypes(["x", "a"]);
    await s.ensureDeviceTypes(["y", "a"]);
    await s.ensureDeviceTypes(["x", "a"]);
    await s.ensureDeviceTypes(["y", "a"]);
    expect(s.fetches, [Duration.zero, Duration.zero]);
  });

  test("a cached load does not make an unavailable type retry", () async {
    final s = await _loaded(["a"]);
    await s.ensureDeviceTypes(["x"]);
    await s.loadDeviceTypes();
    s.fetches.clear();
    await s.ensureDeviceTypes(["x"]);
    expect(s.fetches, isEmpty);
  });

  test("forgetting lets an unavailable type be retried", () async {
    final s = await _loaded(["a"]);
    await s.ensureDeviceTypes(["x"]);
    s.forgetUnavailableDeviceTypes();
    s.fetches.clear();
    await s.ensureDeviceTypes(["x"]);
    expect(s.fetches, [Duration.zero]);
  });

  test("joining a running cached load still fetches fresh", () async {
    final s = _State(["a"]);
    s.gate = Completer();
    final cached = s.loadDeviceTypes();
    final ensured = s.ensureDeviceTypes(["b"]);
    await pumpEventQueue();
    expect(s.fetches, [metadataMaxAge], reason: "the cached load is in flight");
    s.backend = ["a", "b"];
    s.gate!.complete();
    s.gate = null;
    await Future.wait([cached, ensured]);
    expect(s.fetches.last, Duration.zero);
    expect(s.deviceTypes.keys, contains("b"));
  });

  test("a failed reload waits before trying again", () async {
    final s = await _loaded(["a"]);
    s.fail = true;
    await s.ensureDeviceTypes(["b"]);
    await s.ensureDeviceTypes(["b"]);
    expect(s.fetches, [Duration.zero]);
  });

  test("a failed reload marks nothing, so the next attempt fetches the type",
      () async {
    final s = await _loaded(["a"]);
    s.deviceTypesRetryDelay = Duration.zero;
    s.fail = true;
    await s.ensureDeviceTypes(["b"]);
    s.fail = false;
    s.backend = ["a", "b"];
    await s.ensureDeviceTypes(["b"]);
    expect(s.fetches, [Duration.zero, Duration.zero]);
    expect(s.deviceTypes.keys, contains("b"));
  });
}
