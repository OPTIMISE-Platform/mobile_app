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

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/location.dart';

import 'fake_backend.dart';
import 'golden_helper.dart';

const _path = "/device-manager/locations";

Map<String, dynamic> _json(String id, String name,
        {List<String> devices = const [],
        List<String> groups = const [],
        String image = ""}) =>
    {
      "id": id,
      "name": name,
      "description": "",
      "image": image,
      "device_ids": devices,
      "device_group_ids": groups,
    };

Location _location(String id, String name,
        {List<String> devices = const [], List<String> groups = const []}) =>
    Location(id, name, "", "", List.of(devices), List.of(groups));

void main() {
  late FakeBackend backend;
  late int notifications;
  void countNotification() => notifications++;

  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  setUp(() {
    backend = FakeBackend();
    serveGoldenBackend(backend);
    notifications = 0;
    AppState().addListener(countNotification);
  });

  tearDown(() {
    AppState().removeListener(countNotification);
    resetAppStateForGolden();
    resetGoldenBackend();
  });

  // Round-tripped through JSON, as the wire would: toJson nests the Lists.
  Map<String, dynamic> lastBody(String method) => jsonDecode(jsonEncode(
          backend.requests.lastWhere((r) => r.method == method).data))
      as Map<String, dynamic>;

  /// Waits until [method] has reached the backend, for a request held open.
  Future<void> requestArrived(String method) async {
    for (var i = 0; i < 500; i++) {
      if (backend.requests.any((r) => r.method == method)) return;
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    fail("$method never reached the backend");
  }

  group("create", () {
    test("adds the location the platform returns", () async {
      backend.serveJson("POST", "$_path/", 200, _json("new-1", "Garage"));

      final created = await AppState().createLocation("Garage");

      expect(lastBody("POST")["name"], "Garage");
      expect(created.id, "new-1");
      expect(AppState().locations.map((l) => l.id), ["new-1"]);
      expect(AppState().locations.single, same(created));
      expect(notifications, greaterThan(0));
    });

    test("is not added twice when a reload brought it in meanwhile", () async {
      backend.serveJson("POST", "$_path/", 200, _json("new-1", "Garage"));
      final hold = Completer<void>();
      backend.holds["POST $_path/"] = hold;

      final creating = AppState().createLocation("Garage");
      await requestArrived("POST");
      AppState().locations.add(_location("new-1", "Garage"));
      hold.complete();
      await creating;

      expect(AppState().locations.map((l) => l.id), ["new-1"]);
    });

    test("a failed create adds nothing and throws", () async {
      backend.serveJson("POST", "$_path/", 500, null);

      await expectLater(AppState().createLocation("Garage"), throwsA(anything));

      expect(AppState().locations, isEmpty);
    });
  });

  group("rename", () {
    test("swaps in the location the platform returns", () async {
      final old = _location("location-1", "Kitchen", devices: ["device-1"]);
      AppState().locations.add(old);
      // The platform's answer wins over what was sent, e.g. a trimmed name.
      backend.serveJson("PUT", "$_path/location-1", 200,
          _json("location-1", "Pantry", devices: ["device-1"]));

      await AppState().renameLocation("location-1", " Pantry ");

      expect(lastBody("PUT")["name"], " Pantry ");
      expect(lastBody("PUT")["device_ids"], ["device-1"]);
      expect(AppState().locations.single, isNot(same(old)));
      expect(AppState().locations.single.name, "Pantry");
      expect(AppState().locationsForDevice("device-1").single,
          same(AppState().locations.single));
      expect(notifications, greaterThan(0));
    });

    test("a failed save leaves the old name in memory", () async {
      final old = _location("location-1", "Kitchen");
      AppState().locations.add(old);
      backend.serveJson("PUT", "$_path/location-1", 500, null);

      await expectLater(
          AppState().renameLocation("location-1", "Pantry"), throwsA(anything));

      expect(lastBody("PUT")["name"], "Pantry", reason: "the save was tried");
      expect(AppState().locations.single, same(old));
      expect(old.name, "Kitchen");
    });

    test("swaps by id when the list shifted during the save", () async {
      AppState().locations.add(_location("location-1", "Kitchen"));
      backend.serveJson(
          "PUT", "$_path/location-1", 200, _json("location-1", "Pantry"));
      final hold = Completer<void>();
      backend.holds["PUT $_path/location-1"] = hold;

      final saving = AppState().renameLocation("location-1", "Pantry");
      await requestArrived("PUT");
      AppState().locations.insert(0, _location("location-0", "Attic"));
      hold.complete();
      await saving;

      expect(AppState().locations.map((l) => l.name), ["Attic", "Pantry"]);
    });

    test("keeps the shown image when the returned one fails to load",
        () async {
      const image = "https://images.test/kitchen.png";
      final shown = Container();
      AppState().locations.add(
          Location("location-1", "Kitchen", "", image, [], [])
            ..imageWidget = shown);
      // The image request itself is unmatched and answers 404.
      backend.serveJson("PUT", "$_path/location-1", 200,
          _json("location-1", "Pantry", image: image));

      await AppState().renameLocation("location-1", "Pantry");

      expect(AppState().locations.single.name, "Pantry");
      expect(AppState().locations.single.imageWidget, same(shown));
    });

    test("an unknown id throws without a request", () async {
      await expectLater(AppState().renameLocation("missing", "Pantry"),
          throwsA(isA<StateError>()));

      expect(backend.requests, isEmpty);
    });
  });

  group("devices", () {
    test("a saved device list reaches locationsForDevice", () async {
      AppState().locations
          .add(_location("location-1", "Kitchen", devices: ["device-1"]));
      // Builds the index before the edit, so a stale one would show below.
      expect(AppState().locationsForDevice("device-1"), hasLength(1));
      expect(AppState().locationsForDevice("device-2"), isEmpty);
      backend.serveJson("PUT", "$_path/location-1", 200,
          _json("location-1", "Kitchen", devices: ["device-2"]));

      await AppState().setLocationDevices("location-1", ["device-2"]);

      expect(lastBody("PUT")["device_ids"], ["device-2"]);
      expect(AppState().locations.single.device_ids, ["device-2"]);
      expect(AppState().locationsForDevice("device-1"), isEmpty);
      expect(AppState().locationsForDevice("device-2").single.id, "location-1");
      expect(notifications, greaterThan(0));
    });

    test("a failed save leaves the old device list in memory", () async {
      final old =
          _location("location-1", "Kitchen", devices: ["device-1"]);
      AppState().locations.add(old);
      expect(AppState().locationsForDevice("device-1"), hasLength(1));
      backend.serveJson("PUT", "$_path/location-1", 500, null);

      await expectLater(
          AppState().setLocationDevices("location-1", ["device-2"]),
          throwsA(anything));

      expect(AppState().locations.single, same(old));
      expect(old.device_ids, ["device-1"]);
      expect(AppState().locationsForDevice("device-1"), hasLength(1));
      expect(AppState().locationsForDevice("device-2"), isEmpty);
    });
  });

  group("groups", () {
    test("swaps in the saved group list", () async {
      AppState().locations
          .add(_location("location-1", "Kitchen", groups: ["group-1"]));
      backend.serveJson("PUT", "$_path/location-1", 200,
          _json("location-1", "Kitchen", groups: ["group-2"]));

      await AppState().setLocationGroups("location-1", ["group-2"]);

      expect(lastBody("PUT")["device_group_ids"], ["group-2"]);
      expect(AppState().locations.single.device_group_ids, ["group-2"]);
    });

    test("a failed save leaves the old group list in memory", () async {
      final old = _location("location-1", "Kitchen", groups: ["group-1"]);
      AppState().locations.add(old);
      backend.serveJson("PUT", "$_path/location-1", 500, null);

      await expectLater(
          AppState().setLocationGroups("location-1", ["group-2"]),
          throwsA(anything));

      expect(AppState().locations.single, same(old));
      expect(old.device_group_ids, ["group-1"]);
    });
  });

  group("delete", () {
    test("removes by id even when the list order changed meanwhile",
        () async {
      AppState().locations.addAll([
        _location("location-a", "Attic", devices: ["device-a"]),
        _location("location-b", "Basement", devices: ["device-b"]),
      ]);
      expect(AppState().locationsForDevice("device-b"), hasLength(1));
      backend.serveJson("DELETE", "$_path/location-b", 200, null);
      final hold = Completer<void>();
      backend.holds["DELETE $_path/location-b"] = hold;

      final deleting = AppState().deleteLocation("location-b");
      await requestArrived("DELETE");
      final reordered = AppState().locations.reversed.toList();
      AppState().locations
        ..clear()
        ..addAll(reordered);
      hold.complete();
      await deleting;

      expect(AppState().locations.map((l) => l.id), ["location-a"]);
      expect(AppState().locationsForDevice("device-b"), isEmpty);
      expect(AppState().locationsForDevice("device-a"), hasLength(1));
      expect(notifications, greaterThan(0));
    });

    test("a failed delete keeps the location", () async {
      AppState().locations.add(_location("location-1", "Kitchen"));
      backend.serveJson("DELETE", "$_path/location-1", 500, null);

      await expectLater(
          AppState().deleteLocation("location-1"), throwsA(anything));

      expect(AppState().locations.map((l) => l.id), ["location-1"]);
    });
  });
}
