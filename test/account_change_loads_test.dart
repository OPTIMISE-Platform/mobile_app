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

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_class.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/models/notification.dart' as app;
import 'package:mobile_app/services/device_classes.dart';
import 'package:mobile_app/services/device_types.dart';
import 'package:mobile_app/services/mgw/reachability.dart';
import 'package:mobile_app/services/mgw/storage.dart';
import 'package:mobile_app/shared/account_epoch.dart';
import 'package:mobile_app/shared/error_reporter.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

Future<void> _until(bool Function() condition) async {
  for (var i = 0; i < 300 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// A loader of [AppState] that swaps a list or map in memory once its request
/// to [path] is answered with [body].
typedef _Loader = ({
  String name,
  String path,
  Object Function(String id) body,
  void Function(FakeBackend backend) serveRest,
  Future<Object?> Function() load,
  Iterable<String> Function() ids,
  // Serialized on a mutex rather than shared through JoinedLoad.
  bool mutex,
});

/// loadNetworks takes a context it does not read.
class _Context extends Fake implements BuildContext {}

final _loaders = <_Loader>[
  (
    name: "loadLocations",
    path: "/device-repository/locations",
    body: (id) => [
          {
            "id": id,
            "name": id,
            "description": "",
            "image": "",
            "device_ids": <String>[],
            "device_group_ids": <String>[],
          }
        ],
    serveRest: (_) {},
    load: () => AppState().loadLocations(),
    ids: () => AppState().locations.map((l) => l.id),
    mutex: true,
  ),
  (
    name: "loadDeviceGroups",
    path: "/device-repository/device-groups",
    body: (id) => [_group(id)],
    serveRest: (backend) {
      for (final id in ["old", "new"]) {
        backend.serveJson(
            "GET", "/device-repository/device-groups/$id", 200, _group(id));
      }
    },
    load: () => AppState().loadDeviceGroups(),
    ids: () => AppState().deviceGroups.map((g) => g.id),
    mutex: true,
  ),
  (
    name: "loadNetworks",
    path: "/device-repository/extended-hubs",
    body: (id) => [
          {
            "id": id,
            "name": id,
            "hash": "",
            "owner_id": "owner-1",
            "shared": false,
            "device_local_ids": <String>[],
            "device_ids": <String>[],
            "connection_state": "online",
          }
        ],
    serveRest: (_) {},
    load: () => AppState().loadNetworks(_Context()),
    ids: () => AppState().networks.map((n) => n.id),
    mutex: true,
  ),
  (
    name: "loadAspects",
    path: "/device-repository/aspects",
    body: (id) => [
          {"id": id, "name": id, "sub_aspects": null}
        ],
    serveRest: (_) {},
    load: () => AppState().loadAspects(),
    ids: () => AppState().aspects.keys,
    mutex: false,
  ),
  (
    name: "loadNotifications",
    path: "/notifications-v2/notifications",
    body: (id) => {
          "notifications": [
            app.Notification("2026-09-30T00:00:00Z", "m", "user", id, false, "t")
                .toJson()
          ],
          "offset": 0,
          "limit": 10000,
          "total": 1,
        },
    serveRest: (_) {},
    load: () => AppState().loadNotifications(null),
    ids: () => AppState().notifications.map((n) => n.id),
    mutex: true,
  ),
];

Map<String, dynamic> _group(String id) => {
      "id": id,
      "name": id,
      "image": "",
      "criteria": <Map<String, dynamic>>[],
      "device_ids": <String>[],
      "attributes": null,
    };

void main() {
  late FakeBackend backend;
  final shown = <String>[];

  int requestsTo(String path) =>
      backend.requests.where((r) => r.uri.path == path).length;

  /// What Auth._cleanup does to the state in memory.
  Future<void> logout() async {
    AccountEpoch.advance();
    await AppState().onLogout();
  }

  setUpAll(() async {
    await setUpGoldenEnvironment();
    await MgwStorage.init();
  });

  setUp(() {
    backend = FakeBackend();
    serveGoldenBackend(backend);
    ErrorReporter.resetForTest();
    shown.clear();
    ErrorReporter.present = shown.add;
  });

  tearDown(() async {
    await AppState().onLogout();
    resetAppStateForGolden();
    resetGoldenBackend();
    ErrorReporter.resetForTest();
    ErrorReporter.present = (_) {};
  });

  for (final l in _loaders) {
    final key = "GET ${l.path}";

    test("${l.name} outliving a logout leaves the list empty, and a call "
        "after it fetches its own", () async {
      backend.serveJson("GET", l.path, 200, l.body("old"));
      l.serveRest(backend);
      final oldGate = Completer<void>();
      backend.holds[key] = oldGate;

      final old = l.load();
      await _until(() => requestsTo(l.path) == 1);
      expect(requestsTo(l.path), 1);
      await logout();
      // Holds and routes are looked up per request, after the hold.
      final currentGate = Completer<void>();
      backend.holds[key] = currentGate;
      final current = l.load();
      oldGate.complete();
      final oldResult = await old;

      expect(l.ids(), isEmpty, reason: "the old account's result is dropped");
      if (oldResult is bool) expect(oldResult, isFalse);
      expect(shown, isEmpty);

      backend.serveJson("GET", l.path, 200, l.body("new"));
      currentGate.complete();
      final currentResult = await current;
      expect(requestsTo(l.path), 2,
          reason: "the call after the logout did not join the old load");
      expect(l.ids(), ["new"]);
      if (currentResult is bool) expect(currentResult, isTrue);
    });

    if (l.mutex) {
      test("${l.name} queued behind a load across a logout loads nothing",
          () async {
        backend.serveJson("GET", l.path, 200, l.body("old"));
        l.serveRest(backend);
        final gate = Completer<void>();
        backend.holds[key] = gate;

        final running = l.load();
        await _until(() => requestsTo(l.path) == 1);
        expect(requestsTo(l.path), 1);
        final queued = l.load();
        await logout();
        gate.complete();
        await Future.wait([running, queued]);

        expect(requestsTo(l.path), 1,
            reason: "the queued call belongs to the gone account");
        expect(l.ids(), isEmpty);
        expect(shown, isEmpty);
      });
    }

    test("${l.name} failing after a logout reports nothing", () async {
      final gate = Completer<void>();
      backend.holds[key] = gate;
      backend.failures[key] = DioExceptionType.connectionError;

      final old = l.load();
      await _until(() => requestsTo(l.path) == 1);
      expect(requestsTo(l.path), 1);
      await logout();
      gate.complete();
      await old;

      expect(shown, isEmpty,
          reason: "the failure is not the next account's to be told about");
      expect(l.ids(), isEmpty);
    });
  }

  test("a Settings reload outliving a logout neither fails nor announces",
      () async {
    const path = "/device-repository/aspects";
    backend.serveJson("GET", path, 200, [
      {"id": "old", "name": "old", "sub_aspects": null}
    ]);
    final gate = Completer<void>();
    backend.holds["GET $path"] = gate;
    var pushes = 0;
    final sub = AppState().refreshPressed.listen((_) => pushes++);
    addTearDown(sub.cancel);

    Object? error;
    final reload =
        AppState().reloadMetadata().catchError((Object e) => error = e);
    await _until(() => requestsTo(path) == 1);
    expect(requestsTo(path), 1);
    await logout();
    gate.complete();
    await reload;
    await pumpEventQueue();

    expect(error, isNull,
        reason: "the dropped results are not the refresh failing");
    expect(pushes, 0);
    expect(AppState().aspects, isEmpty);
  });

  // An account change wipes the stored rows but leaves the networks in
  // memory, so only the epoch moves here.
  test("a network load whose gateway probe outlives an account change "
      "assigns no network to the next account's groups", () async {
    // DeviceGroup matches devices on the first 57 characters of their id.
    final deviceId = "urn:infai:ses:device:${"0" * 36}:service";
    const host = "192.0.2.10";
    await MgwStorage.ReplacePairedMGWs(
        [MGW("gw", "gw", "core-1", host, networkId: "net-1")]);
    addTearDown(() async {
      await MgwStorage.ReplacePairedMGWs([]);
      MgwReachability.forget();
    });
    MgwReachability.forget();
    backend.serveJson("GET", "/device-repository/extended-hubs", 200, [
      {
        "id": "net-1",
        "name": "Net",
        "hash": "",
        "owner_id": "owner-1",
        "shared": false,
        "device_local_ids": <String>[],
        "device_ids": [deviceId.substring(0, 57)],
        "connection_state": "online",
      }
    ]);
    // Built while no network is loaded: the constructor looks one up itself.
    final group = DeviceGroup("g-next", "Next", [], "", [deviceId], null);
    expect(group.network, isNull);
    // The liveness probe of the merge.
    final probe = Completer<void>();
    backend.holds["GET /"] = probe;

    final load = AppState().loadNetworks(_Context());
    // The constructor's discovery may hold the probe too; the load is in its
    // merge once the networks are in.
    await _until(() =>
        AppState().networks.isNotEmpty &&
        backend.requests.any((r) => r.uri.path == "/"));
    expect(AppState().networks.map((n) => n.id), ["net-1"]);
    AccountEpoch.advance();
    AppState().deviceGroups.add(group);
    probe.complete();
    await load;

    expect(group.network, isNull);
  }, timeout: const Timeout(Duration(seconds: 30)));

  test("an init outliving a logout leaves the next session uninitialized",
      () async {
    final readGate = Completer<void>();
    var reads = 0;
    AppState().fetchDeviceClasses = (maxAge, {serveStale}) async {
      reads++;
      await readGate.future;
      return [DeviceClass("stored", "Stored", "")];
    };
    AppState().fetchDeviceTypes = (maxAge, {serveStale}) async => [];
    addTearDown(() {
      AppState().fetchDeviceTypes = (maxAge, {serveStale}) =>
          DeviceTypesService.getDeviceTypes(null, maxAge, serveStale);
      AppState().fetchDeviceClasses = (maxAge, {serveStale}) =>
          DeviceClassesService.getDeviceClasses(
              maxAge: maxAge, serveStale: serveStale);
    });

    final old = AppState().init();
    await _until(() => reads == 1);
    expect(reads, 1);
    await logout();
    readGate.complete();
    await old;

    expect(AppState().initialized, isFalse,
        reason: "otherwise the next account's ensureInitialized skips init");
    expect(AppState().deviceClasses, isEmpty);

    await AppState().ensureInitialized();
    expect(AppState().initialized, isTrue);
    expect(reads, 2, reason: "the next session ran its own init");
    expect(AppState().deviceClasses.keys, ["stored"]);
  });
}
