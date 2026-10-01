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
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/services/mgw/auth_service.dart';
import 'package:mobile_app/services/mgw/storage.dart';

import 'test_helper.dart';

const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
const _shared = "mgw-device-credentials";

/// Secure storage answered on its platform channel, which, unlike the plugin's
/// map mock, lets a test hold one call open while others run.
class _ChannelStore {
  final data = <String, String>{};

  /// Calls named "method key" that wait for their completer.
  final holds = <String, Completer<void>>{};

  /// Calls named "method key" that fail as a Keystore error would.
  final fails = <String>{};
  final calls = <String>[];

  Future<Object?> handle(MethodCall call) async {
    final args = (call.arguments as Map).cast<String, Object?>();
    final key = args["key"] as String?;
    final name = "${call.method} $key";
    calls.add(name);
    await holds[name]?.future;
    if (fails.contains(name)) {
      throw PlatformException(code: "KeystoreUnavailable");
    }
    switch (call.method) {
      case "read":
        return data[key];
      case "write":
        data[key!] = args["value"] as String;
        return null;
      case "delete":
        data.remove(key);
        return null;
      case "containsKey":
        return data.containsKey(key);
      case "readAll":
        return data;
      case "deleteAll":
        data.clear();
        return null;
    }
    return null;
  }

  Future<void> until(String name) async {
    for (var i = 0; i < 1000 && !calls.contains(name); i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(calls, contains(name));
  }
}

String _credentials(String login) =>
    jsonEncode(DeviceUserCredentials("id-$login", login, "s"));

void main() {
  late _ChannelStore store;

  setUpAll(() async {
    setUpTestEnvironment();
    await MgwStorage.init();
  });

  setUp(() async {
    store = _ChannelStore();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, store.handle);
    MgwStorage.restartForTest();
    await MgwStorage.ReplacePairedMGWs([
      MGW("a.local", "A", "c1", "10.0.0.1", networkId: "n1", pairingId: "p1"),
      MGW("b.local", "B", "c2", "10.0.0.2", networkId: "n2", pairingId: "p2"),
    ]);
  });

  test("a pairing stored while the migration runs is not overwritten",
      () async {
    store.data[_shared] = _credentials("shared");
    store.data["mgw-session"] = "shared-session";
    store.data["mgw-session-expiration"] = "2099-01-01T00:00:00Z";
    final copying = Completer<void>();
    store.holds["write mgw-session:p1"] = copying;

    final load = MgwStorage.LoadCredentials("p1");
    await store.until("write mgw-session:p1");
    // Paired again while the shared set is being copied to this entry.
    final pairing = MgwStorage.StoreCredentials(
        "p1", DeviceUserCredentials("id-new", "paired", "s"));
    await pumpEventQueue();
    copying.complete();
    await load;
    await pairing;

    expect(jsonDecode(store.data[MgwStorage.credentialsKeyOf("p1")]!)["login"],
        "paired");
  });

  test("a failing migration is logged once, runs once per start and does not "
      "hold up pairings with credentials of their own", () async {
    store.data[_shared] = _credentials("shared");
    store.data[MgwStorage.credentialsKeyOf("p1")] = _credentials("p1");
    store.data[MgwStorage.credentialsKeyOf("p2")] = _credentials("p2");
    store.fails.add("delete $_shared");
    final reading = Completer<void>();
    store.holds["read $_shared"] = reading;
    final printed = <String>[];

    await runZoned(() async {
      final first = await MgwStorage.LoadCredentials("p1")
          .timeout(const Duration(seconds: 2));
      expect(first.login, "p1", reason: "answered while the migration waits");
      reading.complete();
      await store.until("delete $_shared");
      for (var i = 0; i < 3; i++) {
        expect((await MgwStorage.LoadCredentials("p1")).login, "p1");
        expect((await MgwStorage.LoadCredentials("p2")).login, "p2");
      }
      await pumpEventQueue();
    }, zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => printed.add(line)));

    expect(store.calls.where((c) => c == "read $_shared"), hasLength(1));
    expect(
        printed.where((l) =>
            l.contains("Could not move the shared gateway credentials")),
        hasLength(1));
    expect(store.data, contains(_shared), reason: "kept for the next start");

    MgwStorage.restartForTest();
    store.fails.clear();
    await MgwStorage.LoadCredentials("p1");
    await store.until("delete $_shared");
    await pumpEventQueue();
    expect(store.calls.where((c) => c == "read $_shared"), hasLength(2));
    expect(store.data, isNot(contains(_shared)));
  });
}
