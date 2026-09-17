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

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/services/api_available.dart';

Network _network(String id, List<String>? gatewayHosts) {
  final network = Network(id, id, false, const [], const [],
      DeviceConnectionStatus.unknown, "", "");
  network.localGatewayHosts = gatewayHosts;
  return network;
}

void main() {
  group("servedLocally", () {
    test("matches a gateway host", () {
      final networks = [_network("n1", ["192.168.1.5"])];
      expect(
          ApiAvailableService.servedLocally(networks, "http://192.168.1.5:8080/core/api"),
          isTrue);
    });

    test("ignores the port a gateway address carries", () {
      // A gateway on a non-default port is stored as host:port, while the host
      // of a parsed uri never has one.
      final networks = [_network("n1", ["192.168.1.5:8081"])];
      expect(
          ApiAvailableService.servedLocally(networks, "http://192.168.1.5:8081/core/api"),
          isTrue);
    });

    test("keeps looking after a network whose gateways do not match", () {
      final networks = [
        _network("n1", ["192.168.1.5"]),
        _network("n2", ["192.168.1.9"]),
      ];
      expect(
          ApiAvailableService.servedLocally(networks, "http://192.168.1.9/x"),
          isTrue);
    });

    test("a network without a gateway makes nothing local", () {
      final networks = [_network("n1", null), _network("n2", const [])];
      expect(
          ApiAvailableService.servedLocally(
              networks, "https://api.senergy.infai.org/x"),
          isFalse);
    });

    test("a cloud host is not local even next to a paired gateway", () {
      final networks = [_network("n1", ["192.168.1.5"])];
      expect(
          ApiAvailableService.servedLocally(
              networks, "https://api.senergy.infai.org/x"),
          isFalse);
    });

    test("compares the host case insensitively", () {
      final networks = [_network("n1", ["MGW-Core.local"])];
      expect(ApiAvailableService.servedLocally(networks, "http://mgw-core.local/x"),
          isTrue);
    });

    test("a uri without a host is not local", () {
      final networks = [_network("n1", ["192.168.1.5"])];
      expect(ApiAvailableService.servedLocally(networks, "/relative/path"), isFalse);
    });
  });
}
