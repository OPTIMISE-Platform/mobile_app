/*
 * Copyright (c) 2026 InfAI (CC SES)
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

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/models/content_variable.dart';
import 'package:mobile_app/models/smart_service.dart';

// The value an instance returns for a multiple parameter, taken over by the
// edit and upgrade screens through the value setter.
void main() {
  const a = '{"device_selection":{"device_id":"urn:infai:ses:device:a","service_id":null,"path":null},"label":"A"}';
  const b = '{"device_selection":{"device_id":"urn:infai:ses:device:b","service_id":null,"path":null},"label":"B"}';
  final options = [
    SmartServiceParameterOption("", "A", a, null, null),
    SmartServiceParameterOption("", "B", b, null, null),
  ];

  SmartServiceExtendedParameter parameter({required bool multiple}) => SmartServiceExtendedParameter(
      "indoor", "Innenfühler", "", null, null, multiple, options, ContentVariable.string, null, null, null, true);

  test("a multiple value given as JSON text becomes the list", () {
    // as the automation-engine returns it since 2026-10-22
    final p = parameter(multiple: true)..value = json.encode([a, b]);
    expect(p.value, [a, b]);
    expect(p.toSmartServiceParameter().value_label, "A, B");
  });

  test("a multiple value given as list stays the list", () {
    final p = parameter(multiple: true)..value = [b];
    expect(p.value, [b]);
  });

  test("a multiple value that is no JSON list stays as it is", () {
    expect((parameter(multiple: true)..value = "not json").value, "not json");
    expect((parameter(multiple: true)..value = a).value, a);
  });

  test("a single value that looks like a JSON list stays text", () {
    final p = parameter(multiple: false)..value = json.encode([a]);
    expect(p.value, json.encode([a]));
  });
}
