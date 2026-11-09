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
import 'package:mobile_app/live/raw_value_source.dart';

void main() {
  group('RawValueSource.fromUrl', () {
    test('reads the URL the PV Visualization model builds', () {
      final source = RawValueSource.fromUrl(
          'https://api.senergy.infai.org/db/v3/raw-value?device_id=urn:infai:ses:device:abc&service_id=urn:infai:ses:service:def&column=metrics.power&not_null=true&target_characteristic_id=urn:infai:ses:characteristic:w&concept_id=urn:infai:ses:concept:p');
      expect(source, isNotNull);
      expect(source!.deviceId, 'urn:infai:ses:device:abc');
      expect(source.serviceId, 'urn:infai:ses:service:def');
      expect(source.column, 'metrics.power');
      expect(source.targetCharacteristicId, 'urn:infai:ses:characteristic:w');
      expect(source.conceptId, 'urn:infai:ses:concept:p');
    });

    test('target characteristic and concept are optional', () {
      final source = RawValueSource.fromUrl('https://x.test/db/v3/raw-value?device_id=d&service_id=s&column=a.b&not_null=true');
      expect(source!.targetCharacteristicId, isNull);
      expect(source.conceptId, isNull);
    });

    test('decodes encoded parameters', () {
      final source = RawValueSource.fromUrl(
          'https://x.test/db/v3/raw-value?device_id=urn%3Ainfai%3Ases%3Adevice%3Aabc&service_id=s&column=list.%2A.value&target_characteristic_id=a%20b');
      expect(source!.deviceId, 'urn:infai:ses:device:abc');
      expect(source.column, 'list.*.value');
      expect(source.targetCharacteristicId, 'a b');
    });

    test('the host and a path prefix do not matter', () {
      expect(RawValueSource.fromUrl('http://localhost:8080/db/v3/raw-value?device_id=d&service_id=s&column=c'), isNotNull);
      expect(RawValueSource.fromUrl('https://x.test/api/db/v3/raw-value?device_id=d&service_id=s&column=c'), isNotNull);
    });

    test('other paths are null', () {
      expect(RawValueSource.fromUrl('https://x.test/db/v3/export?device_id=d&service_id=s&column=c'), isNull);
      expect(RawValueSource.fromUrl('https://x.test/db/v3/raw-value/extra?device_id=d&service_id=s&column=c'), isNull);
      expect(RawValueSource.fromUrl('https://x.test/other?device_id=d&service_id=s&column=c'), isNull);
    });

    test('a missing or empty device, service or column is null', () {
      expect(RawValueSource.fromUrl('https://x.test/db/v3/raw-value?service_id=s&column=c'), isNull);
      expect(RawValueSource.fromUrl('https://x.test/db/v3/raw-value?device_id=d&column=c'), isNull);
      expect(RawValueSource.fromUrl('https://x.test/db/v3/raw-value?device_id=d&service_id=s'), isNull);
      expect(RawValueSource.fromUrl('https://x.test/db/v3/raw-value?device_id=&service_id=s&column=c'), isNull);
    });

    test('garbage is null', () {
      expect(RawValueSource.fromUrl(''), isNull);
      expect(RawValueSource.fromUrl('http://['), isNull);
    });
  });
}
