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

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/mixins/network_mixin.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/services/api_available.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/services/mgw/discovery.dart';
import 'package:mobile_app/services/mgw/gateway_host.dart';
import 'package:mobile_app/services/mgw/reachability.dart';
import 'package:mobile_app/services/mgw/storage.dart';

import 'golden_helper.dart';

DiscoveredGateway _found(String ip, int port, {String coreId = "c1"}) =>
    DiscoveredGateway(
        coreId: coreId,
        name: "MGW-Core-$coreId",
        hostname: "mgw-$coreId.local",
        ip: ip,
        port: port);

void main() {
  group("gatewayAddress", () {
    test("keeps a non-default port and leaves the default one out", () {
      expect(gatewayAddress("192.168.1.5", 8081), "192.168.1.5:8081");
      expect(gatewayAddress("192.168.1.5", defaultGatewayPort), "192.168.1.5");
    });

    test("brackets an IPv6 literal", () {
      expect(gatewayAddress("fd00::5", 8081), "[fd00::5]:8081");
      expect(gatewayAddress("fd00::5", defaultGatewayPort), "[fd00::5]");
    });

    test("is what a discovered gateway pairs with", () {
      expect(_found("192.168.1.5", 8081).address, "192.168.1.5:8081");
      expect(
          DiscoveredGateway(
                  coreId: "", name: "n", hostname: "mgw.local", ip: "", port: 8081)
              .address,
          "mgw.local:8081");
    });
  });

  group("gatewayAuthority with IPv6", () {
    test("does not read the last group of a bare literal as a port", () {
      // "fe80::1" ends in ":1"; taken as a port, the request went to host
      // "fe80:" on port 1.
      expect(gatewayAuthority("fe80::1"), "[fe80::1]:8080");
      expect(gatewayAuthority("2001:db8::8081"), "[2001:db8::8081]:8080");
    });

    test("adds the default port to a bracketed literal only without one", () {
      expect(gatewayAuthority("[fd00::5]"), "[fd00::5]:8080");
      expect(gatewayAuthority("[fd00::5]:8081"), "[fd00::5]:8081");
    });

    test("yields a URL whose host and port parse back", () {
      final uri = Uri.parse("http://${gatewayAuthority("[fd00::5]:8081")}/");
      expect(uri.host, "fd00::5");
      expect(uri.port, 8081);
      final zoned = Uri.parse("http://${gatewayAuthority("fe80::1%wlan0")}/");
      expect(zoned.port, 8080);
    });

    test("host part matches what a parsed URI reports", () {
      for (final stored in ["[fd00::5]:8081", "[fd00::5]", "fd00::5"]) {
        final uri = Uri.parse("http://${gatewayAuthority(stored)}/");
        expect(gatewayHostOnly(stored), uri.host, reason: stored);
      }
      expect(gatewayHostOnly("192.168.1.5:8081"), "192.168.1.5");
    });

    test("a request to a bracketed gateway counts as served locally", () {
      final network = Network("n", "N", false, [], [],
          DeviceConnectionStatus.online, "h", "o")
        ..localGatewayHosts = ["[fd00::5]:8081"];
      expect(
          ApiAvailableService.servedLocally(
              [network], "http://[fd00::5]:8081/core/api"),
          isTrue);
    });
  });

  group("zone ids", () {
    test("the host part of a zoned literal matches what a URI reports", () {
      for (final stored in ["fe80::1%eth0", "[fe80::1%eth0]:8081"]) {
        final uri = Uri.parse("http://${gatewayAuthority(stored)}/");
        expect(gatewayHostOnly(stored), uri.host, reason: stored);
      }
    });

    test("a raw zone 25 and its escaped form address the same host", () {
      // Interface 25: raw "%25", escaped "%2525".
      expect(gatewayAuthority("fe80::1%25"), "[fe80::1%2525]:8080");
      expect(gatewayAuthority("fe80::1%2525"), "[fe80::1%2525]:8080");
      expect(gatewayAuthority("[fe80::1%25]:8081"), "[fe80::1%2525]:8081");
      for (final stored in ["fe80::1%25", "fe80::1%2525", "[fe80::1%25]:8081"]) {
        final uri = Uri.parse("http://${gatewayAuthority(stored)}/");
        expect(gatewayHostOnly(stored), uri.host, reason: stored);
      }
    });

    test("a request to a zoned gateway counts as served locally", () {
      final network = Network("n", "N", false, [], [],
          DeviceConnectionStatus.online, "h", "o")
        ..localGatewayHosts = ["fe80::1%eth0"];
      expect(
          ApiAvailableService.servedLocally([network],
              "http://${gatewayAuthority("fe80::1%eth0")}/core/api"),
          isTrue);
    });
  });

  group("parseGatewayInput", () {
    test("drops scheme, path, query and fragment", () {
      expect(parseGatewayInput(" http://192.168.1.5:8081/ "), "192.168.1.5:8081");
      expect(parseGatewayInput("HTTPS://mgw.local/core/api"), "mgw.local");
      expect(parseGatewayInput("mgw.local?x=1#y"), "mgw.local");
      expect(parseGatewayInput("[fd00::5]:8081/x"), "[fd00::5]:8081");
    });

    test("writes the port as a number and leaves the default one out", () {
      expect(parseGatewayInput("mgw.local:08081"), "mgw.local:8081");
      expect(parseGatewayInput("mgw.local:08080"), "mgw.local");
      expect(parseGatewayInput("192.168.001.005"), "192.168.1.5");
    });

    test("keeps a plain host, address or IPv6 literal", () {
      expect(parseGatewayInput("192.168.1.5"), "192.168.1.5");
      expect(parseGatewayInput("fe80::1"), "[fe80::1]");
    });

    test("refuses what is no host with an optional port", () {
      for (final input in [
        "",
        "http://",
        "a b",
        "user@host",
        "host:",
        ":8080",
        "host:abc",
        "host:0",
        "host:99999",
        "256.1.1.1",
        "192.168.1",
        "1.2.3.4.5",
        "%",
        "-",
        "fe80::zz",
      ]) {
        expect(parseGatewayInput(input), isNull, reason: input);
      }
    });
  });

  group("sameGatewayAddress", () {
    test("treats the default port as implied", () {
      expect(sameGatewayAddress("192.168.1.5", "192.168.1.5:8080"), isTrue);
      expect(sameGatewayAddress("MGW.local", "mgw.local"), isTrue);
    });

    test("tells ports apart", () {
      expect(sameGatewayAddress("192.168.1.5:8081", "192.168.1.5"), isFalse);
    });

    test("never matches an empty address", () {
      expect(sameGatewayAddress("", ""), isFalse);
    });
  });

  group("pickAddress", () {
    test("prefers IPv4 over an IPv6 address listed first", () {
      expect(
          MgwDiscoveryService.pickAddress([
            InternetAddress("fe80::1"),
            InternetAddress("fd00::5"),
            InternetAddress("192.168.1.5"),
          ]),
          "192.168.1.5");
    });

    test("prefers a routable IPv6 address over a link-local one", () {
      expect(
          MgwDiscoveryService.pickAddress(
              [InternetAddress("fe80::1"), InternetAddress("fd00::5")]),
          "fd00::5");
    });

    test("falls back to link-local, and to null without any", () {
      expect(MgwDiscoveryService.pickAddress([InternetAddress("fe80::1")]),
          "fe80::1");
      expect(MgwDiscoveryService.pickAddress([]), isNull);
      expect(MgwDiscoveryService.pickAddress(null), isNull);
    });
  });

  group("movedAddress", () {
    test("a gateway on a non-default port that did not move stays", () {
      final mgw = MGW("mgw-c1.local", "MGW", "c1", "192.168.1.5:8081");
      expect(NetworkMixin.movedAddress(mgw, [_found("192.168.1.5", 8081)]),
          isNull);
    });

    test("a gateway on the default port that did not move stays", () {
      final mgw = MGW("mgw-c1.local", "MGW", "c1", "192.168.1.5");
      expect(
          NetworkMixin.movedAddress(
              mgw, [_found("192.168.1.5", defaultGatewayPort)]),
          isNull);
    });

    test("a moved gateway is reported with its port", () {
      final mgw = MGW("mgw-c1.local", "MGW", "c1", "192.168.1.5:8081");
      final moved =
          NetworkMixin.movedAddress(mgw, [_found("192.168.1.6", 8081)]);
      expect(moved?.address, "192.168.1.6:8081");
    });

    test("a changed port alone counts as moved", () {
      final mgw = MGW("mgw-c1.local", "MGW", "c1", "192.168.1.5:8081");
      expect(
          NetworkMixin.movedAddress(mgw, [_found("192.168.1.5", 8082)])
              ?.address,
          "192.168.1.5:8082");
    });
  });

  group("address refresh on start and resume", () {
    setUpAll(() async {
      await setUpGoldenEnvironment();
      await MgwStorage.init();
      // The constructor starts a discovery of its own; a call made while it
      // runs returns at once, so it has to be over before the tests call.
      AppState();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });

    tearDown(() async {
      MgwDiscoveryService.discoverOverride = null;
      MgwReachability.probeOverride = null;
      MgwReachability.forget();
      await MgwStorage.ReplacePairedMGWs([]);
      resetAppStateForGolden();
    });

    test("keeps the stored port of a gateway that did not move", () async {
      await MgwStorage.ReplacePairedMGWs([
        MGW("mgw-c1.local", "MGW", "c1", "192.168.1.5:8081",
            networkId: "net-1")
      ]);
      MgwDiscoveryService.discoverOverride =
          (_) async => [_found("192.168.1.5", 8081)];
      final probed = <String>[];
      MgwReachability.probeOverride = (host, expect) async {
        probed.add(host);
        return MgwReport(
            status: MgwStatus.ok,
            address: gatewayAuthority(host),
            checkedAt: DateTime.utc(2026));
      };

      await AppState().manageNetworkDiscovery();

      final stored = await MgwStorage.LoadPairedMGWs();
      expect(stored.single.ip, "192.168.1.5:8081");
      expect(probed, ["192.168.1.5:8081"]);
    });

    test("stores a moved gateway's new address with its port", () async {
      await MgwStorage.ReplacePairedMGWs([
        MGW("mgw-c1.local", "MGW", "c1", "192.168.1.5:8081",
            networkId: "net-1")
      ]);
      MgwDiscoveryService.discoverOverride =
          (_) async => [_found("192.168.1.9", 8081)];
      MgwReachability.probeOverride = (host, expect) async => MgwReport(
          status: MgwStatus.ok,
          address: gatewayAuthority(host),
          checkedAt: DateTime.utc(2026));

      await AppState().manageNetworkDiscovery();

      final stored = await MgwStorage.LoadPairedMGWs();
      expect(stored.single.ip, "192.168.1.9:8081");
      expect(AppState().gateways.single.ip, "192.168.1.9:8081");
    });

    test("entries stored before the network id split start no scan",
        () async {
      // A network id in coreId never matches a discovered core id.
      await MgwStorage.ReplacePairedMGWs([
        MGW.fromJson({
          "hostname": "10.0.0.1",
          "mDNSServiceName": "10.0.0.1",
          "coreId": "urn:infai:ses:hub:n1",
          "ip": "10.0.0.1",
        })
      ]);
      var scans = 0;
      MgwDiscoveryService.discoverOverride = (_) async {
        scans++;
        return [];
      };
      MgwReachability.probeOverride = (host, expect) async => MgwReport(
          status: MgwStatus.ok,
          address: gatewayAuthority(host),
          checkedAt: DateTime.utc(2026));

      await AppState().manageNetworkDiscovery();

      expect(scans, 0);
    });

    test("the same address in two networks is routed only for the network "
        "that answers", () async {
      await MgwStorage.ReplacePairedMGWs([
        MGW("192.168.0.2", "Home", "", "192.168.0.2", networkId: "n1"),
        MGW("192.168.0.2", "Office", "", "192.168.0.2", networkId: "n2"),
      ]);
      final home = Network("n1", "Home", false, [], [],
          DeviceConnectionStatus.online, "h1", "o");
      final office = Network("n2", "Office", false, [], [],
          DeviceConnectionStatus.online, "h2", "o");
      AppState().networks.addAll([home, office]);
      MgwReachability.probeOverride = (host, expect) async => MgwReport(
          status: expect == "n1" ? MgwStatus.ok : MgwStatus.foreign,
          address: gatewayAuthority(host),
          checkedAt: DateTime.utc(2026));

      await AppState().mergeGatewaysWithNetworks();

      expect(home.localGatewayHosts, ["192.168.0.2"]);
      expect(office.localGatewayHosts, isNull);
    });

    test("does not drop a gateway paired while the scan ran", () async {
      await MgwStorage.ReplacePairedMGWs([
        MGW("mgw-c1.local", "MGW", "c1", "192.168.1.5:8081",
            networkId: "net-1")
      ]);
      MgwDiscoveryService.discoverOverride = (_) async {
        // Paired from the pairing page while the resume scan is running.
        await MgwStorage.StorePairedMGW(
            MGW("10.0.0.7", "10.0.0.7", "", "10.0.0.7", networkId: "net-2"));
        return [_found("192.168.1.9", 8081)];
      };
      MgwReachability.probeOverride = (host, expect) async => MgwReport(
          status: MgwStatus.ok,
          address: gatewayAuthority(host),
          checkedAt: DateTime.utc(2026));

      await AppState().manageNetworkDiscovery();

      final stored = await MgwStorage.LoadPairedMGWs();
      expect(stored.map((m) => m.ip), ["192.168.1.9:8081", "10.0.0.7"]);
    });
  });
}
