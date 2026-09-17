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
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/services/mgw/discovery.dart';
import 'package:mobile_app/services/mgw/gateway_host.dart';

Uint8List _txt(String value) => Uint8List.fromList(utf8.encode(value));

void main() {
  group("readTxt", () {
    test("decodes a record", () {
      expect(
          MgwDiscoveryService.readTxt({"core_id": _txt("d109d982")}, "core_id"),
          equals("d109d982"));
    });

    test("is empty for a missing, null or empty record", () {
      expect(MgwDiscoveryService.readTxt({}, "core_id"), equals(""));
      expect(MgwDiscoveryService.readTxt(null, "core_id"), equals(""));
      expect(MgwDiscoveryService.readTxt({"core_id": null}, "core_id"),
          equals(""));
      expect(
          MgwDiscoveryService.readTxt({"core_id": Uint8List(0)}, "core_id"),
          equals(""));
    });

    test("trims the value", () {
      expect(MgwDiscoveryService.readTxt({"core_id": _txt(" d1 ")}, "core_id"),
          equals("d1"));
    });
  });

  group("fromService", () {
    test("takes host, port, address and core id", () {
      final gateway = MgwDiscoveryService.fromService(
        name: "MGW-Core-d109d982",
        host: "mgw.local",
        port: 8081,
        address: "192.168.1.5",
        txt: {"core_id": _txt("d109d982")},
      );
      expect(gateway, isNotNull);
      expect(gateway!.hostname, equals("mgw.local"));
      expect(gateway.port, equals(8081));
      expect(gateway.ip, equals("192.168.1.5"));
      expect(gateway.coreId, equals("d109d982"));
      expect(gateway.name, equals("MGW-Core-d109d982"));
    });

    test("is null without a host, which leaves nothing to address", () {
      expect(
          MgwDiscoveryService.fromService(name: "x", host: null, port: 8080),
          isNull);
      expect(MgwDiscoveryService.fromService(name: "x", host: "", port: 8080),
          isNull);
    });

    test("falls back to the host when the service has no name", () {
      final gateway =
          MgwDiscoveryService.fromService(host: "mgw.local", port: 8080);
      expect(gateway!.name, equals("mgw.local"));
    });

    test("falls back to the default port when none is reported", () {
      // An address built from port 0 is unreachable and explains nothing, so a
      // missing port has to mean the default.
      expect(MgwDiscoveryService.fromService(host: "mgw.local")!.port,
          equals(defaultGatewayPort));
      expect(MgwDiscoveryService.fromService(host: "mgw.local", port: 0)!.port,
          equals(defaultGatewayPort));
    });

    test("tolerates a service without address and core id", () {
      final gateway =
          MgwDiscoveryService.fromService(host: "mgw.local", port: 8080);
      expect(gateway!.ip, equals(""));
      expect(gateway.coreId, equals(""));
    });
  });

  group("gatewayAuthority", () {
    test("adds the default port when none is given", () {
      expect(gatewayAuthority("192.168.1.5"), equals("192.168.1.5:8080"));
      expect(gatewayAuthority("mgw.local"), equals("mgw.local:8080"));
    });

    test("keeps a port the user or the core supplied", () {
      expect(gatewayAuthority("192.168.1.5:8081"), equals("192.168.1.5:8081"));
    });
  });

  group("coreServiceType", () {
    test("is browsable and valid for the platform APIs", () {
      // nsd rejects a type whose first label has an underscore or more than 15
      // characters, which is what the per-core type the installer uses today
      // runs into.
      expect(RegExp(r'^_[a-zA-Z0-9-]{1,15}\._(tcp|udp)$')
          .hasMatch(MgwDiscoveryService.coreServiceType), isTrue);
    });
  });
}
