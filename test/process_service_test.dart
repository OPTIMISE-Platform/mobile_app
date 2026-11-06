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

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/exceptions/unexpected_status_code_exception.dart';
import 'package:mobile_app/services/process_service.dart';

import 'golden_helper.dart';
import 'process_backend.dart';

void main() {
  setUpAll(() async {
    await setUpGoldenEnvironment();
  });

  tearDown(resetGoldenBackend);

  test("lists are read page by page until total is reached", () async {
    final backend = ProcessBackend(
      deployments: [
        for (var i = 0; i < 150; i++) deploymentJson("dep-$i", "Process $i")
      ],
      instances: [
        for (var i = 0; i < 101; i++)
          instanceJson("inst-$i", "dep-$i", "Process $i")
      ],
    );
    serveGoldenBackend(backend);

    final deployments = await ProcessService.getDeployments();
    final instances = await ProcessService.getInstances();

    expect(deployments.length, 150);
    expect(deployments.last.id, "dep-149");
    expect(instances.length, 101);
    final offsets = backend.requests
        .map((r) => "${r.uri.path.split("/").last}@"
            "${r.uri.queryParameters["offset"]}")
        .toList();
    expect(offsets, [
      "deployments@0",
      "deployments@100",
      "instances@0",
      "instances@100",
    ]);
  });

  test("a deployment is parsed with its network, an instance with its times",
      () async {
    final backend = ProcessBackend(
      deployments: [
        deploymentJson("d1", "Heating",
            networkId: "urn:infai:ses:hub:1", description: "Keeps warm"),
        // network_id is absent for the cloud.
        {"id": "d2", "name": "Cloud only"},
      ],
      instances: [
        instanceJson("i1", "d1", "Heating",
            lastActivityAt: "2026-11-06T12:00:00.000Z"),
      ],
    );
    serveGoldenBackend(backend);

    final deployments = await ProcessService.getDeployments();
    expect(deployments[0].networkId, "urn:infai:ses:hub:1");
    expect(deployments[0].description, "Keeps warm");
    expect(deployments[1].networkId, "");
    final instance = (await ProcessService.getInstances()).single;
    expect(instance.isRunning, isTrue);
    expect(instance.lastSeen, DateTime.utc(2026, 11, 6, 12));
  });

  test("debug data is parsed, an unknown wait kind does not fail it", () async {
    final backend = ProcessBackend(debugs: {
      "i1": {
        "instance": {},
        "active": [],
        "waits": [
          {"element_id": "Event_dev", "kind": "device_event", "extra": true}
        ],
        "incidents": [
          {"error_message": "boom"}
        ],
        "elements": [],
      }
    });
    serveGoldenBackend(backend);

    final debug = await ProcessService.getDebug("i1");
    expect(debug.waits.single.kind, "device_event");
    expect(debug.waits.single.isTimer, isFalse);
    expect(debug.incidents.single.message, "boom");
  });

  test("an error status is thrown as UnexpectedStatusCodeException", () async {
    final backend = ProcessBackend();
    serveGoldenBackend(backend);

    await expectLater(ProcessService.getDebug("missing"),
        throwsA(isA<UnexpectedStatusCodeException>()));
    backend.failures["GET $processesBase/deployments"] =
        DioExceptionType.connectionError;
    await expectLater(ProcessService.getDeployments(), throwsA(anything));
  });

  test("forEachLimited never runs more than the limit at once", () async {
    var running = 0, peak = 0;
    final done = <int>[];
    await ProcessService.forEachLimited(List.generate(10, (i) => i), 4,
        (i) async {
      running++;
      if (running > peak) peak = running;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      running--;
      done.add(i);
    });
    expect(peak, 4);
    expect(done.length, 10);
  });

  test("forEachLimited carries on after an action throws", () async {
    final done = <int>[];
    await ProcessService.forEachLimited([1, 2, 3], 1, (i) async {
      if (i == 2) throw StateError("x");
      done.add(i);
    });
    expect(done, [1, 3]);
  });
}
