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
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/models/mgw_deployment.dart';
import 'package:mobile_app/models/mgw_module.dart';

/// The fixtures are responses recorded from a running gateway, so a change to
/// the wire format shows up here rather than on a device.
List<dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync());

Map<String, dynamic> _fixtureMap(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync());

void main() {
  group("Module.fromJson", () {
    late List<Module> modules;

    setUp(() {
      modules = _fixture('mgw_modules_reduced.json')
          .map((m) => Module.fromJson(m))
          .toList();
    });

    test("reads the descriptive fields", () {
      final module = modules.firstWhere(
          (m) => m.id == "github.com/SENERGY-Platform/device-management-service/mgw-module");
      expect(module.name, equals("Device Management Service"));
      expect(module.version, equals("v0.1.4"));
      expect(module.source,
          equals("github.com/SENERGY-Platform/mgw-module-repository"));
      expect(module.channel, equals("main"));
      expect(module.author, equals("InfAI (CC SES)"));
    });

    test("reads tags, both empty and populated", () {
      final withTags =
          modules.firstWhere((m) => m.id.endsWith("test-mod-a"));
      final withoutTags =
          modules.firstWhere((m) => m.id.endsWith("mgw-wmbus-module"));
      expect(withTags.tags,
          equals(["all-attributes", "test", "reference"]));
      expect(withoutTags.tags, isEmpty);
    });

    test("tolerates an empty description and author", () {
      final module = modules.firstWhere((m) => m.id.endsWith("mgw-wmbus-module"));
      expect(module.description, equals(""));
      expect(module.author, equals(""));
    });

    test("parses a module that has no deployment", () {
      final module = modules.firstWhere((m) => m.id.endsWith("test-mod-a"));
      expect(module.is_deployed, isFalse);
      // The zero value the gateway sends: empty id and a year-one timestamp.
      expect(module.deployment.id, equals(""));
      expect(module.deployment.created, equals("0001-01-01T00:00:00Z"));
      expect(module.deployment.state, equals(0));
    });

    test("reports a healthy deployment", () {
      final module = modules.firstWhere((m) =>
          m.id == "github.com/SENERGY-Platform/device-management-service/mgw-module");
      expect(module.is_deployed, isTrue);
      expect(module.deployment.enabled, isTrue);
      expect(module.deployment.state, equals(1));
      expect(module.deployment.id,
          equals("01a080e0-94b4-7c0c-9f82-7d75d4208347"));
      expect(module.deployment.module_version, equals("v0.1.4"));
    });

    test("reports a deployed but disabled module", () {
      final module = modules.firstWhere((m) => m.id.endsWith("mgw-wmbus-module"));
      expect(module.is_deployed, isTrue);
      expect(module.deployment.enabled, isFalse);
      expect(module.deployment.state, equals(0));
    });
  });

  group("Endpoint.fromJson", () {
    test("reads the fields the local device path needs", () {
      final endpoints = _fixtureMap('mgw_core_manager_endpoints.json')
          .values
          .map((e) => Endpoint.fromJson(e))
          .toList();
      expect(endpoints, hasLength(1));
      expect(endpoints.first.id,
          equals("61097ecaf809d918ff0561536313867b84efd8e5"));
      expect(
          endpoints.first.location,
          equals(
              "/endpoints/deployment/01a080e0-94b4-7c0c-9f82-7d75d4208347/api"));
      expect(endpoints.first.ref,
          equals("01a080e0-94b4-7c0c-9f82-7d75d4208347"));
    });
  });

  group("MGW.fromJson", () {
    test("keeps the network binding", () {
      final mgw = MGW.fromJson({
        "hostname": "mgw.local",
        "mDNSServiceName": "MGW-Core-d109d982",
        "coreId": "d109d982",
        "ip": "192.168.1.5",
        "networkId": "urn:infai:ses:hub:abc",
      });
      expect(mgw.coreId, equals("d109d982"));
      expect(mgw.networkId, equals("urn:infai:ses:hub:abc"));
    });

    test("falls back to coreId for an entry stored before the split", () {
      final mgw = MGW.fromJson({
        "hostname": "mgw.local",
        "mDNSServiceName": "MGW",
        "coreId": "urn:infai:ses:hub:abc",
        "ip": "192.168.1.5",
      });
      expect(mgw.networkId, equals("urn:infai:ses:hub:abc"));
    });
  });
}
