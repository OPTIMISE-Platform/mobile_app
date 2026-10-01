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

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mobile_app/services/mgw/auth_service.dart';
import 'package:mobile_app/services/mgw/restricted.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/services/mgw/storage.dart';

import 'test_helper.dart';

Future<List<String>> _stored() async =>
    (await MgwStorage.LoadPairedMGWs()).map((m) => "${m.hostname}@${m.ip}").toList();

void main() {
  setUpAll(() async {
    setUpTestEnvironment();
    FlutterSecureStorage.setMockInitialValues({});
    await MgwStorage.init();
  });

  setUp(() => MgwStorage.ReplacePairedMGWs([]));

  test("entries alike in every field but their pairing are not the same",
      () {
    MGW entry(String pairingId) => MGW("a.local", "A", "c1", "10.0.0.1",
        networkId: "n1", pairingId: pairingId);

    expect(MgwStorage.isSameEntry(entry("p1"), entry("p2")), isFalse);
    expect(MgwStorage.isSameEntry(entry("p1"), entry("p1")), isTrue);
    expect(MgwStorage.isSameEntry(entry("p1"), entry("")), isTrue,
        reason: "a copy taken before the entry was stored");
  });

  test("pairing a discovered gateway again replaces its entry", () async {
    await MgwStorage.StorePairedMGW(
        MGW("mgw.local", "MGW", "c1", "192.168.1.5:8081", networkId: "n1"));
    await MgwStorage.StorePairedMGW(
        MGW("mgw.local", "MGW", "c1", "192.168.1.9:8081", networkId: "n1"));

    expect(await _stored(), ["mgw.local@192.168.1.9:8081"]);
  });

  test("the core id decides even when the hostname changed", () async {
    await MgwStorage.StorePairedMGW(MGW("old.local", "MGW", "c1", "10.0.0.1"));
    await MgwStorage.StorePairedMGW(MGW("new.local", "MGW", "c1", "10.0.0.2"));

    expect(await _stored(), ["new.local@10.0.0.2"]);
  });

  test("different core ids are different gateways at any address", () async {
    await MgwStorage.StorePairedMGW(MGW("a.local", "A", "c1", "10.0.0.1"));
    await MgwStorage.StorePairedMGW(MGW("a.local", "B", "c2", "10.0.0.1"));

    expect(await _stored(), hasLength(2));
  });

  test("a gateway added by address is matched by its address", () async {
    await MgwStorage.StorePairedMGW(
        MGW("10.0.0.1", "10.0.0.1", "", "10.0.0.1", networkId: "n1"));
    await MgwStorage.StorePairedMGW(
        MGW("10.0.0.1:8080", "10.0.0.1:8080", "", "10.0.0.1:8080",
            networkId: "n1"));

    expect(await _stored(), ["10.0.0.1:8080@10.0.0.1:8080"]);
  });

  test("the same address bound to two networks stays two gateways", () async {
    // Two homes, both with their gateway at the router's first address.
    await MgwStorage.StorePairedMGW(
        MGW("192.168.0.2", "Home", "", "192.168.0.2", networkId: "n1"));
    await MgwStorage.StorePairedMGW(
        MGW("192.168.0.2", "Office", "", "192.168.0.2", networkId: "n2"));

    expect(await _stored(), hasLength(2));
  });

  test("keeps the position and collapses entries stored twice before",
      () async {
    await MgwStorage.ReplacePairedMGWs([
      MGW("a.local", "A", "c1", "10.0.0.1"),
      MGW("b.local", "B", "c2", "10.0.0.2"),
      MGW("a.local", "A", "c1", "10.0.0.1"),
    ]);
    await MgwStorage.StorePairedMGW(MGW("a.local", "A", "c1", "10.0.0.3"));

    expect(await _stored(), ["a.local@10.0.0.3", "b.local@10.0.0.2"]);
  });

  test("pairing again by address keeps the core id and mDNS name", () async {
    await MgwStorage.StorePairedMGW(MGW("mgw.local", "MGW-Core-c1", "c1",
        "192.168.1.5:8081",
        networkId: "n1"));
    await MgwStorage.StorePairedMGW(MGW("192.168.1.5:8081", "192.168.1.5:8081",
        "", "192.168.1.5:8081",
        networkId: "n1"));

    final stored = (await MgwStorage.LoadPairedMGWs()).single;
    expect(stored.coreId, "c1");
    expect(stored.hostname, "mgw.local");
    expect(stored.mDNSServiceName, "MGW-Core-c1");
    expect(stored.ip, "192.168.1.5:8081");
  });

  test("a gateway bound anew replaces the entry it was paired from", () async {
    final old = MGW("10.0.0.1", "10.0.0.1", "", "10.0.0.1", networkId: "n1");
    await MgwStorage.StorePairedMGW(old);
    await MgwStorage.StorePairedMGW(
        MGW("10.0.0.1", "10.0.0.1", "", "10.0.0.1", networkId: "n2"),
        replacing: old);

    final stored = await MgwStorage.LoadPairedMGWs();
    expect(stored.map((m) => m.networkId), ["n2"]);
  });

  test("removing a pairing removes only the entry shown", () async {
    // The same address bound to two networks, as two entries.
    final home =
        MGW("192.168.0.2", "Home", "", "192.168.0.2", networkId: "n1");
    final office =
        MGW("192.168.0.2", "Office", "", "192.168.0.2", networkId: "n2");
    await MgwStorage.ReplacePairedMGWs([home, office]);
    await MgwStorage.StoreCredentials(
        home.pairingId, DeviceUserCredentials("id", "home", "s"));
    await MgwStorage.StoreCredentials(
        office.pairingId, DeviceUserCredentials("id", "office", "s"));

    await MgwStorage.RemovePairedMGW(home);

    expect((await MgwStorage.LoadPairedMGWs()).map((m) => m.networkId), ["n2"]);
    await expectLater(MgwStorage.LoadCredentials(home.pairingId),
        throwsA(isA<MgwCredentialsMissing>()));
    expect((await MgwStorage.LoadCredentials(office.pairingId)).login, "office",
        reason: "the remaining entry keeps its credentials");

    await MgwStorage.RemovePairedMGW(office);
    expect(await MgwStorage.LoadPairedMGWs(), isEmpty);
    await expectLater(MgwStorage.LoadCredentials(office.pairingId),
        throwsA(isA<MgwCredentialsMissing>()));
  });

  test("removing a gateway whose address moved since it was shown", () async {
    final shown = MGW("mgw.local", "MGW", "c1", "192.168.1.5:8081",
        networkId: "n1");
    // The resume refresh rewrote the address after the sheet opened.
    await MgwStorage.ReplacePairedMGWs([
      MGW("mgw.local", "MGW", "c1", "192.168.1.9:8081", networkId: "n1"),
      MGW("b.local", "B", "c2", "10.0.0.2", networkId: "n2"),
    ]);

    expect(await MgwStorage.RemovePairedMGW(shown), isTrue);
    expect((await MgwStorage.LoadPairedMGWs()).map((m) => m.coreId), ["c2"]);
  });

  test("an entry added by address is found by hostname and network", () async {
    final shown = MGW("10.0.0.1", "10.0.0.1", "", "10.0.0.1", networkId: "n1");
    await MgwStorage.ReplacePairedMGWs(
        [MGW("10.0.0.1", "10.0.0.1", "", "10.0.0.1:8081", networkId: "n1")]);

    expect(await MgwStorage.RemovePairedMGW(shown), isTrue);
    expect(await MgwStorage.LoadPairedMGWs(), isEmpty);
  });

  test("nothing stored any more: nothing removed, the session stays", () async {
    final b = MGW("b.local", "B", "c2", "10.0.0.2",
        networkId: "n2", pairingId: "pairing-b");
    FlutterSecureStorage.setMockInitialValues({
      MgwService.sessionKeyOf("pairing-b"): "s",
      MgwService.sessionExpirationKeyOf("pairing-b"): "2099-01-01T00:00:00Z",
    });
    await MgwStorage.ReplacePairedMGWs([b]);

    final removed = await MgwStorage.RemovePairedMGW(
        MGW("a.local", "A", "c1", "10.0.0.1", networkId: "n1"));

    expect(removed, isFalse);
    expect(await MgwStorage.LoadPairedMGWs(), hasLength(1));
    expect(
        await const FlutterSecureStorage()
            .read(key: MgwService.sessionKeyOf("pairing-b")),
        "s");
  });

  group("entries stored before the network id split", () {
    // As written then: the network id in coreId, no networkId key.
    Future<void> storeLegacy(List<Map<String, String>> entries) async {
      await Hive.box<String>("mgw.box")
          .put("connected_mgws_", jsonEncode(entries));
    }

    Map<String, String> legacy(String host) => {
          "hostname": host,
          "mDNSServiceName": host,
          "coreId": "urn:infai:ses:hub:n1",
          "ip": host,
        };

    test("siblings of one network stay separate gateways", () async {
      await storeLegacy([legacy("10.0.0.1"), legacy("10.0.0.2")]);
      final stored = await MgwStorage.LoadPairedMGWs();

      // What pairing one of them again stores.
      final again = stored[1];
      await MgwStorage.StorePairedMGW(
          MGW(again.hostname, again.mDNSServiceName, again.coreId, again.ip,
              networkId: again.networkId),
          replacing: again);

      expect(await _stored(), ["10.0.0.1@10.0.0.1", "10.0.0.2@10.0.0.2"]);
    });

    test("pairing the gateway again from discovery replaces the entry",
        () async {
      await storeLegacy([legacy("192.168.1.5")]);

      await MgwStorage.StorePairedMGW(MGW("mgw.local", "MGW-Core-d109d982",
          "d109d982", "192.168.1.5",
          networkId: "urn:infai:ses:hub:n1"));

      final stored = await MgwStorage.LoadPairedMGWs();
      expect(stored.map((m) => m.coreId), ["d109d982"]);
    });

    test("one is removed, its sibling stays", () async {
      await storeLegacy([legacy("10.0.0.1"), legacy("10.0.0.2")]);
      final stored = await MgwStorage.LoadPairedMGWs();

      expect(await MgwStorage.RemovePairedMGW(stored.first), isTrue);
      expect(await _stored(), ["10.0.0.2@10.0.0.2"]);
    });
  });
}
