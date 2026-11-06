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
import 'package:mobile_app/models/process.dart';

Map<String, dynamic> _instance(String id, String deployment, String createdAt,
        {String state = "running"}) =>
    {
      "id": id,
      "deployment_id": deployment,
      "deployment_name": deployment,
      "state": state,
      "created_at": createdAt,
    };

void main() {
  group("latestInstancePerDeployment", () {
    test("picks the newest created_at per deployment, whatever the order", () {
      final latest = latestInstancePerDeployment([
        _instance("a-new", "dep-a", "2026-11-06T10:00:00Z"),
        _instance("a-old", "dep-a", "2026-11-01T10:00:00Z", state: "completed"),
        _instance("b-old", "dep-b", "2026-11-02T10:00:00Z"),
        _instance("b-new", "dep-b", "2026-11-05T10:00:00Z", state: "completed"),
      ].map(ProcessInstance.fromJson));
      expect(latest.keys, unorderedEquals(["dep-a", "dep-b"]));
      expect(latest["dep-a"]!.id, "a-new");
      expect(latest["dep-b"]!.id, "b-new");
    });

    test("an instance without created_at loses against one with", () {
      final latest = latestInstancePerDeployment([
        {"id": "undated", "deployment_id": "d", "state": "running"},
        _instance("dated", "d", "2026-11-01T10:00:00Z"),
        {"id": "undated-2", "deployment_id": "d", "state": "running"},
      ].map(ProcessInstance.fromJson));
      expect(latest["d"]!.id, "dated");
    });

    test("no instances gives an empty map", () {
      expect(latestInstancePerDeployment(const []), isEmpty);
    });
  });

  group("ProcessDebug", () {
    test("parses a timer wait and the active step", () {
      final debug = ProcessDebug.fromJson({
        "active": [
          {
            "element_id": "Timer_tick",
            "element_type": "intermediateCatchEvent",
            "name": "15 Minuten",
            "since": "2026-11-06T16:07:15.358Z",
            "tokens": 1
          }
        ],
        "waits": [
          {
            "element_id": "Timer_tick",
            "kind": "timer",
            "since": "2026-11-06T16:07:15.358Z",
            "timer": {
              "definition": "PT15M",
              "kind": "duration",
              "due_at": "2026-11-06T16:22:15.358Z"
            }
          }
        ],
        "incidents": [],
        "elements": [
          {"element_id": "Flow_age", "run": 1, "count": 6}
        ],
      });
      expect(debug.waits.single.isTimer, isTrue);
      expect(debug.waits.single.timerDefinition, "PT15M");
      expect(debug.nextTimer(), DateTime.utc(2026, 11, 6, 16, 22, 15, 358));
      expect(debug.stepName("Timer_tick"), "15 Minuten");
      expect(debug.stepName("Unknown_id"), "Unknown_id");
      expect(debug.incidents, isEmpty);
    });

    test("an unknown wait kind keeps its kind and has no timer", () {
      final debug = ProcessDebug.fromJson({
        "waits": [
          {
            "element_id": "Event_msg",
            "kind": "message",
            "since": "2026-11-06T16:07:15Z",
            "correlation": {"anything": 1}
          }
        ],
      });
      final wait = debug.waits.single;
      expect(wait.kind, "message");
      expect(wait.isTimer, isFalse);
      expect(wait.dueAt, isNull);
      expect(debug.nextTimer(), isNull);
    });

    test("the next timer is the earliest due one", () {
      final debug = ProcessDebug.fromJson({
        "waits": [
          {
            "element_id": "late",
            "kind": "timer",
            "timer": {"definition": "PT2H", "due_at": "2026-11-06T18:00:00Z"}
          },
          {
            "element_id": "soon",
            "kind": "timer",
            "timer": {"definition": "PT1H", "due_at": "2026-11-06T17:00:00Z"}
          },
        ],
      });
      expect(debug.nextTimer(), DateTime.utc(2026, 11, 6, 17));
    });

    test("incident message comes from the usual fields, else the raw map", () {
      expect(const ProcessIncident({"error_message": "boom"}).message, "boom");
      expect(const ProcessIncident({"message": "oops"}).message, "oops");
      expect(const ProcessIncident({"code": 7}).message, "{code: 7}");
    });

    test("missing and malformed fields do not throw", () {
      final debug = ProcessDebug.fromJson({
        "active": "nope",
        "waits": [1, null, {"kind": 3}],
        "incidents": [
          {"error_message": "x"},
          "junk"
        ],
      });
      expect(debug.active, isEmpty);
      expect(debug.waits.single.kind, "");
      expect(debug.incidents.single.message, "x");
    });
  });

  test("an incident names its step and time, falling back to the element id", () {
    final named = ProcessIncident({
      "message": "x",
      "element_id": "Task_1",
      "element_name": "Read sensor",
      "time": "2026-11-06T10:00:00Z",
    });
    expect(named.step, "Read sensor");
    expect(named.time, DateTime.utc(2026, 11, 6, 10));
    expect(ProcessIncident({"element_id": "Task_1"}).step, "Task_1");
    expect(ProcessIncident({}).step, "");
    expect(ProcessIncident({}).time, isNull);
  });
}
