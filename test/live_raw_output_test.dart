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
import 'package:mobile_app/live/raw_output.dart';
import 'package:mobile_app/models/concept.dart';
import 'package:mobile_app/models/content.dart';
import 'package:mobile_app/models/content_variable.dart';
import 'package:mobile_app/models/protocol.dart';
import 'package:mobile_app/models/service.dart';

Protocol protocol() => Protocol('proto', 'Proto', [
      ProtocolSegment('seg-json', 'json'),
      ProtocolSegment('seg-text', 'text'),
      ProtocolSegment('seg-xml', 'xml'),
    ]);

ContentVariable variable(String name,
        {String? characteristic, String? function, String type = ContentVariable.none, List<ContentVariable>? subs}) =>
    ContentVariable(null, name, characteristic, null, null, function, type, subs, null, null);

Content content(String serialization, String segmentId, ContentVariable root) =>
    Content('content-$segmentId', serialization, segmentId, root);

Service service(List<Content> outputs) => Service('service', 'local', 'name', 'description', 'proto', 'event', 'group', null, outputs);

void main() {
  final reading = variable('reading', subs: [
    variable('sensor', subs: [
      variable('humidity', characteristic: 'char-humidity', function: 'fn-measure'),
    ]),
  ]);
  final text = variable('temperature', characteristic: 'char-temp', function: 'fn-temp');
  final levels = variable('levels', type: ContentVariable.list, subs: [
    variable('*', characteristic: 'char-level', function: 'fn-level'),
  ]);
  final color = variable('color', subs: [
    variable('rgb', characteristic: 'char-rgb', type: ContentVariable.list),
  ]);
  final xmlVar = variable('xmlValue', characteristic: 'char-x');

  final outputs = service([
    content('json', 'seg-json', reading),
    content('plain-text', 'seg-text', text),
    content('json', 'seg-json', levels),
    content('json', 'seg-json', color),
    content('xml', 'seg-xml', xmlVar),
  ]);

  group('extractValue', () {
    test('reads a nested json path and returns characteristic and function', () {
      final result = extractValue(outputs, protocol(), {'json': '{"sensor":{"humidity":42.5}}'}, 'reading.sensor.humidity');
      expect(result, isNotNull);
      expect(result!.value, 42.5);
      expect(result.characteristicId, 'char-humidity');
      expect(result.functionId, 'fn-measure');
    });

    test('reads a plain-text segment as the raw string', () {
      final result = extractValue(outputs, protocol(), {'text': '21.5'}, 'temperature');
      expect(result!.value, '21.5');
      expect(result.characteristicId, 'char-temp');
      expect(result.functionId, 'fn-temp');
    });

    test('a * segment reads index 0 of a list', () {
      final result = extractValue(outputs, protocol(), {'json': '[10, 20]'}, 'levels.*');
      expect(result!.value, 10);
      expect(result.characteristicId, 'char-level');
      expect(result.functionId, 'fn-level');
    });

    test('an index without its own entry resolves to the * template', () {
      final result = extractValue(outputs, protocol(), {'json': '[10, 20]'}, 'levels.1');
      expect(result!.value, 20);
      expect(result.characteristicId, 'char-level');
    });

    test('an index beyond the list is null', () {
      expect(extractValue(outputs, protocol(), {'json': '[10, 20]'}, 'levels.5'), isNull);
    });

    test('a missing segment is null', () {
      expect(extractValue(outputs, protocol(), {'text': '21.5'}, 'reading.sensor.humidity'), isNull);
      expect(extractValue(outputs, protocol(), {}, 'temperature'), isNull);
    });

    test('a path not in the outputs is null', () {
      expect(extractValue(outputs, protocol(), {'json': '{"sensor":{"humidity":42.5}}'}, 'reading.sensor.pressure'), isNull);
      expect(extractValue(outputs, protocol(), {'json': '{}'}, 'unknown'), isNull);
    });

    test('an xml segment is skipped', () {
      expect(extractValue(outputs, protocol(), {'xml': '<xmlValue>3</xmlValue>'}, 'xmlValue'), isNull);
    });

    test('a structured value is null', () {
      expect(extractValue(outputs, protocol(), {'json': '{"rgb":[1,2,3]}'}, 'color'), isNull);
      expect(extractValue(outputs, protocol(), {'json': '{"rgb":[1,2,3]}'}, 'color.rgb'), isNull);
    });

    test('a json null leaf is null', () {
      expect(extractValue(outputs, protocol(), {'json': '{"sensor":{"humidity":null}}'}, 'reading.sensor.humidity'), isNull);
    });

    test('malformed json is null', () {
      expect(extractValue(outputs, protocol(), {'json': '{"sensor":'}, 'reading.sensor.humidity'), isNull);
    });

    test('a missing function id is an empty string', () {
      final noFunction = service([content('plain-text', 'seg-text', variable('plain', characteristic: 'char-p'))]);
      final result = extractValue(noFunction, protocol(), {'text': 'x'}, 'plain');
      expect(result!.functionId, '');
      expect(result.characteristicId, 'char-p');
    });
  });

  group('plain-text cast by content variable type', () {
    Object? read(String type, String raw) {
      final svc = service([content('plain-text', 'seg-text', variable('v', characteristic: 'c', type: type))]);
      return extractValue(svc, protocol(), {'text': raw}, 'v')?.value;
    }

    test('float', () {
      expect(read(ContentVariable.float, '21.5'), 21.5);
      expect(read(ContentVariable.float, ' 3 '), 3.0);
      expect(read(ContentVariable.float, '3'), isA<double>());
      expect(read(ContentVariable.float, 'abc'), isNull);
      expect(read(ContentVariable.float, 'NaN'), isNull);
      expect(read(ContentVariable.float, 'Infinity'), isNull);
    });

    test('integer', () {
      expect(read(ContentVariable.integer, '42'), 42);
      expect(read(ContentVariable.integer, '4.5'), isNull);
      expect(read(ContentVariable.integer, ''), isNull);
    });

    test('boolean', () {
      expect(read(ContentVariable.boolean, 'true'), true);
      expect(read(ContentVariable.boolean, 'FALSE'), false);
      expect(read(ContentVariable.boolean, '1'), isNull);
      expect(read(ContentVariable.boolean, 'yes'), isNull);
    });

    test('text and untyped stay strings', () {
      expect(read(ContentVariable.string, '21.5'), '21.5');
      expect(read(ContentVariable.none, ' x '), ' x ');
    });
  });

  group('Concept conversions', () {
    Map<String, dynamic> conceptJson({bool withConversions = false}) => {
          'id': 'concept',
          'name': 'Temperature',
          'base_characteristic_id': 'char-c',
          'characteristics': <dynamic>[],
          if (withConversions)
            'conversions': [
              {
                'from': 'char-f',
                'to': 'char-c',
                'distance': 1,
                'formula': '(x - 32) * 5 / 9',
                'placeholder_name': 'x',
              },
            ],
        };

    test('parses without conversions as null', () {
      final concept = Concept.fromJson(conceptJson());
      expect(concept.conversions, isNull);
      expect(concept.base_characteristic_id, 'char-c');
    });

    test('parses conversions', () {
      final concept = Concept.fromJson(conceptJson(withConversions: true));
      final conversion = concept.conversions!.single;
      expect(conversion.from, 'char-f');
      expect(conversion.to, 'char-c');
      expect(conversion.distance, 1);
      expect(conversion.formula, '(x - 32) * 5 / 9');
      expect(conversion.placeholder_name, 'x');
    });
  });

  test('Protocol parses the platform json', () {
    final protocol = Protocol.fromJson({
      'id': 'proto',
      'name': 'Proto',
      'handler': 'handler',
      'protocol_segments': [
        {'id': 'seg-json', 'name': 'json'},
      ],
      'constraints': <dynamic>[],
    });
    expect(protocol.id, 'proto');
    expect(protocol.name, 'Proto');
    expect(protocol.protocol_segments.single.id, 'seg-json');
    expect(protocol.protocol_segments.single.name, 'json');
  });

  test('Protocol without segments parses as empty', () {
    final protocol = Protocol.fromJson({'id': 'proto', 'protocol_segments': null});
    expect(protocol.protocol_segments, isEmpty);
  });
}
