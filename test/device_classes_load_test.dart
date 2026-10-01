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

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/mixins/device_mixin.dart';
import 'package:mobile_app/models/device_class.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/device_classes.dart';
import 'package:mobile_app/shared/account_epoch.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/shared/http_client_adapter.dart';
import 'package:mobile_app/shared/metadata_cache.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

class _CountingClass extends DeviceClass {
  _CountingClass(String id) : super(id, id, "");

  /// Counts requests like [DeviceClass.loadImage] acts on them: once.
  int imageLoads = 0;

  @override
  void loadImage() => imageLoads = 1;
}

class _State extends ChangeNotifier with DeviceMixin {
  _State() {
    fetchDeviceClasses = (maxAge, {serveStale}) async {
      fetches.add(maxAge);
      final name = fetchedName;
      final gate = this.gate;
      if (gate != null) await gate.future;
      if (fail) throw Exception("offline");
      serveStale?.call(storedAt);
      return [DeviceClass(name, name, "")];
    };
    addListener(() => notifications++);
  }

  bool fail = false;

  /// The id the next fetch returns, read when it starts.
  String fetchedName = "fresh";
  DateTime storedAt = DateTime(2026, 1, 1);
  Completer<void>? gate;
  final fetches = <Duration>[];
  int notifications = 0;

  @override
  Future<void> ensureInitialized() async {}
}

/// Serves `/device-repository/v2/device-classes` from [all], at most [cap]
/// per page, with `X-Total-Count` when [sendTotal]; [ignoreOffset] answers
/// every request with the first page.
class _ClassesBackend implements HttpClientAdapter {
  _ClassesBackend(this.all,
      {this.cap = 1 << 30, this.sendTotal = true, this.ignoreOffset = false});

  final List<Map<String, dynamic>> all;
  final int cap;
  final bool sendTotal;
  final bool ignoreOffset;
  final requests = <Uri>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options.uri);
    if (requests.length > 50) throw StateError("runaway paging");
    final q = options.uri.queryParameters;
    final offset = ignoreOffset ? 0 : int.parse(q["offset"] ?? "0");
    final limit = int.parse(q["limit"] ?? "100");
    final page =
        all.skip(offset).take(limit < cap ? limit : cap).toList();
    return ResponseBody.fromString(jsonEncode(page), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      if (sendTotal) "X-Total-Count": ["${all.length}"],
    });
  }

  @override
  void close({bool force = false}) {}
}

List<Map<String, dynamic>> _classes(int n) => [
      // Names run against the ids, so the name order is not the paging order.
      for (var i = 0; i < n; i++)
        deviceClassJson("c${i.toString().padLeft(5, "0")}", "Class ${n - i}")
    ];

void main() {
  final shown = <String>[];

  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  setUp(() {
    shown.clear();
    ErrorReporter.present = shown.add;
  });
  tearDown(() {
    ErrorReporter.resetForTest();
    resetGoldenBackend();
  });

  group("loading", () {
    test("swaps the classes in and notifies", () async {
      final s = _State()..deviceClasses["old"] = DeviceClass("old", "Old", "");
      DateTime? reported;

      expect(await s.loadDeviceClasses(serveStale: (t) => reported = t),
          isTrue);
      expect(s.deviceClasses.keys, ["fresh"]);
      expect(s.notifications, 1);
      expect(s.fetches, [metadataMaxAge]);
      expect(reported, s.storedAt, reason: "the stored time reaches init");
    });

    test("a failure keeps the classes and reports, unless quiet", () async {
      final s = _State()..deviceClasses["old"] = DeviceClass("old", "Old", "");
      s.fail = true;

      expect(await s.loadDeviceClasses(maxAge: Duration.zero), isFalse);
      expect(shown, ["Could not get device classes"]);
      expect(s.deviceClasses.keys, ["old"]);

      shown.clear();
      expect(await s.loadDeviceClasses(quiet: true), isFalse);
      expect(shown, isEmpty);
      expect(s.deviceClasses.keys, ["old"]);
    });

    test("is in the loading state while the fetch runs, and notifies its "
        "end also after a failure", () async {
      final s = _State()
        ..gate = Completer<void>()
        ..fail = true;
      final loadingWhenNotified = <bool>[];
      s.addListener(() => loadingWhenNotified.add(s.loadingDeviceClasses));

      final load = s.loadDeviceClasses(quiet: true);
      await pumpEventQueue();
      expect(s.loadingDeviceClasses, isTrue);
      s.gate!.complete();
      expect(await load, isFalse);
      expect(s.loadingDeviceClasses, isFalse);
      expect(loadingWhenNotified, [false]);
    });

    test("downloads images of the used classes only, and of a class once its "
        "type has loaded", () async {
      final lamp = _CountingClass("lamp");
      final heating = _CountingClass("heating");
      final s = _State()
        ..deviceTypes["t"] = DeviceType("t", "t", "", "lamp", [], null);
      s.fetchDeviceClasses = (maxAge, {serveStale}) async => [lamp, heating];
      s.fetchDeviceTypes = (maxAge, {serveStale}) async => [
            DeviceType("t", "t", "", "lamp", [], null),
            DeviceType("h", "h", "", "heating", [], null),
          ];

      await s.loadDeviceClasses();
      expect(lamp.imageLoads, 1);
      expect(heating.imageLoads, 0);

      await s.loadDeviceTypes();
      expect(heating.imageLoads, 1);
    });
  });

  test("with the platform's types, images wait for the complete index and "
      "follow the classes it brings", () async {
    final lamp = _CountingClass("lamp");
    final heating = _CountingClass("heating");
    final pumps = _CountingClass("pumps");
    final s = _State()..deviceTypesAreAll = () => true;
    s.fetchDeviceClasses = (maxAge, {serveStale}) async => [lamp, heating, pumps];
    s.fetchDeviceTypes = (maxAge, {serveStale}) async => [
          DeviceType("t", "t", "", "lamp", [], null),
          DeviceType("h", "h", "", "heating", [], null),
          DeviceType("p", "p", "", "pumps", [], null),
        ];
    DeviceInstance device(String id, String type) =>
        DeviceInstance.fromJson(deviceJson(id, id, deviceTypeId: type));

    await s.loadDeviceTypes();
    await s.loadDeviceClasses();
    expect([lamp, heating, pumps].map((c) => c.imageLoads), [0, 0, 0],
        reason: "every platform class is listed until the index is complete");

    s.replaceDeviceIndex([device("a", "t")]);
    expect([lamp, heating, pumps].map((c) => c.imageLoads), [1, 0, 0]);

    // A class that comes with a device, the types unchanged.
    s.noteDevices([device("b", "h")]);
    expect([lamp, heating, pumps].map((c) => c.imageLoads), [1, 1, 0]);
  });

  group("across an account change", () {
    void changeAccount(_State s) {
      AccountEpoch.advance();
      s.clearDeviceData();
      s.fetchedName = "next";
    }

    test("a load that outlives it leaves the map empty, and a call after it "
        "gets its own result", () async {
      final s = _State()..gate = Completer<void>();
      final old = s.loadDeviceClasses();
      await pumpEventQueue();
      expect(s.fetches, hasLength(1));

      changeAccount(s);
      final oldGate = s.gate!;
      s.gate = Completer<void>();
      s.notifications = 0;
      final current = s.loadDeviceClasses();
      oldGate.complete();

      expect(await old, isFalse);
      expect(s.deviceClasses, isEmpty);
      expect(s.notifications, 0);
      await pumpEventQueue();
      expect(s.fetches, hasLength(2), reason: "the new call fetched itself");
      s.gate!.complete();
      expect(await current, isTrue);
      expect(s.deviceClasses.keys, ["next"]);
    });

    test("a fetch that fails after it is not reported", () async {
      final s = _State()
        ..fail = true
        ..gate = Completer<void>();
      final old = s.loadDeviceClasses();
      await pumpEventQueue();

      changeAccount(s);
      s.gate!.complete();

      expect(await old, isFalse);
      expect(s.deviceClasses, isEmpty);
      expect(shown, isEmpty);
    });
  });

  group("fetching", () {
    Future<List<DeviceClass>> fetch(HttpClientAdapter backend) {
      AppHttpClientAdapter.testOverride = backend;
      Auth.headersOverride = () async => {"authorization": "Bearer t"};
      return DeviceClassesService.getDeviceClasses(maxAge: Duration.zero);
    }

    test("pages through every class by id and returns them by name",
        () async {
      final backend = _ClassesBackend(_classes(2500), sendTotal: false);

      final classes = await fetch(backend);

      expect(classes, hasLength(2500));
      expect(backend.requests.map((u) => u.queryParameters["offset"]),
          ["0", "1000", "2000"]);
      expect(backend.requests.map((u) => u.queryParameters["sort"]).toSet(),
          {"id.asc"});
      final names = classes.map((c) => c.name.toLowerCase()).toList();
      expect(names, [...names]..sort());
    });

    test("a backend that caps the page is paged to its total", () async {
      final backend = _ClassesBackend(_classes(250), cap: 100);

      final classes = await fetch(backend);

      expect(classes, hasLength(250));
      expect(backend.requests, hasLength(3));
    });

    test("a backend that ignores the offset ends after a page with nothing "
        "new", () async {
      final backend =
          _ClassesBackend(_classes(1000), sendTotal: false, ignoreOffset: true);

      final classes = await fetch(backend);

      expect(classes, hasLength(1000));
      expect(backend.requests, hasLength(2));
    });

    test("an empty or null answer is no classes", () async {
      expect(await fetch(_ClassesBackend([])), isEmpty);

      final backend = FakeBackend()
        ..serveJson("GET", "/device-repository/v2/device-classes", 200, null);
      expect(await fetch(backend), isEmpty);
    });
  });
}
