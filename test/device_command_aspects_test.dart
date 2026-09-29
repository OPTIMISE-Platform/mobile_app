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

import "dart:convert";

import "package:flutter_test/flutter_test.dart";
import "package:mobile_app/models/device_state.dart";
import "package:mobile_app/services/settings.dart";

import "test_helper.dart";

DeviceState _state(List<String> aspectIds, {String? groupId}) => DeviceState(
    null, groupId == null ? "service-1" : null, null, "function-1", null, false, groupId, groupId == null ? null : "class-1",
    groupId == null ? "device-1" : null, null, null,
    aspectIds: aspectIds);

Map<String, dynamic> _commandJson(DeviceState state) => jsonDecode(jsonEncode(state.toCommand().toJson()));

void main() {
  setUpAll(() {
    setUpTestEnvironment();
  });
  setUp(() async {
    await Settings.init();
  });
  tearDown(() async {
    await Settings.clear();
    await Settings.close();
  });

  test("a multi-aspect command carries the list and its first entry", () {
    final json = _commandJson(_state(["b", "a"]));

    expect(json["aspect_ids"], ["a", "b"]);
    expect(json["aspect_id"], "a",
        reason: "an older device-command reads aspect_id alone, and a newer one adds it to the list");
  });

  test("a group command carries the list as well", () {
    final json = _commandJson(_state(["b", "a"], groupId: "group-1"));

    expect(json["group_id"], "group-1");
    expect(json["aspect_ids"], ["a", "b"]);
    expect(json["aspect_id"], "a");
  });

  test("a single-aspect command changes only by the list", () {
    final json = _commandJson(_state(["a"]));

    expect(json["aspect_ids"], ["a"]);
    expect(json..remove("aspect_ids"), {
      "function_id": "function-1",
      "device_id": "device-1",
      "group_id": null,
      "device_class_id": null,
      "service_id": "service-1",
      "aspect_id": "a",
      "characteristic_id": null,
      "input": null,
    });
  });

  test("a command without aspect sends no list", () {
    final json = _commandJson(_state([]));

    expect(json.containsKey("aspect_ids"), isFalse);
    expect(json["aspect_id"], isNull);
  });
}
