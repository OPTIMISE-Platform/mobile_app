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

// Parity tests of the local converter against the Go converter service
// (SENERGY-Platform/converter). Each group names the Go test it mirrors; the
// "Go probe" table holds results of running govaluate v3.0.0 with the
// service's custom functions on the same expressions.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/live/conversion/converter.dart';
import 'package:mobile_app/live/conversion/casts.dart';
import 'package:mobile_app/live/conversion/expression.dart';

final converter = LocalConverter();

dynamic cast(dynamic value, String from, String to) =>
    converter.convert(value, from, to);

dynamic ext(
  dynamic value,
  String formula, {
  String from = 'foo',
  String to = 'bar',
  String placeholder = 'x',
  int distance = -1,
}) => converter.convert(
  value,
  from,
  to,
  extensions: [
    ConversionEdge(
      from: from,
      to: to,
      distance: distance,
      formula: formula,
      placeholderName: placeholder,
    ),
  ],
);

dynamic eval(String formula, [dynamic x]) =>
    Expression.parse(formula).evaluate({'x': x});

Matcher throwsConversion() => throwsA(isA<ConversionException>());

/// Numbers in parameters are doubles, as after the converter's input cleanup.
dynamic _doubles(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is Map) return {for (final e in v.entries) e.key: _doubles(e.value)};
  if (v is List) return [for (final e in v) _doubles(e)];
  return v;
}

void main() {
  test('the built-in graph has the 40 edges of the Go service', () {
    expect(builtInCasts, hasLength(40));
    final pairs = builtInCasts.map((e) => '${e.from}>${e.to}').toSet();
    expect(pairs, hasLength(40));
  });

  // converter/lib/converter/tests/cast_test.go
  group('cast_test.go', () {
    void expectRgb(dynamic out, int r, int g, int b) {
      expect(out, isA<Map>());
      expect((out as Map)['r'], r);
      expect(out['g'], g);
      expect(out['b'], b);
    }

    test('TestColorHexShortF', () {
      expectRgb(
        cast('#FFF', Characteristics.hex, Characteristics.rgb),
        255,
        255,
        255,
      );
    });
    test('TestColorHexF', () {
      expectRgb(
        cast('#FFFFFF', Characteristics.hex, Characteristics.rgb),
        255,
        255,
        255,
      );
    });
    test('TestColorHex0', () {
      expectRgb(
        cast('#000000', Characteristics.hex, Characteristics.rgb),
        0,
        0,
        0,
      );
    });
    test('TestColorHexShort0', () {
      expectRgb(
        cast('#000', Characteristics.hex, Characteristics.rgb),
        0,
        0,
        0,
      );
    });
    test('TestColorRgb255', () {
      expect(
        cast(
          {'r': 255.0, 'g': 255.0, 'b': 255.0},
          Characteristics.rgb,
          Characteristics.hex,
        ),
        '#ffffff',
      );
    });
    test('TestColorRgb0', () {
      expect(
        cast(
          {'r': 0.0, 'g': 0.0, 'b': 0.0},
          Characteristics.rgb,
          Characteristics.hex,
        ),
        '#000000',
      );
    });
    test('hex without hash and mixed case (rgb.go prepends #)', () {
      expectRgb(
        cast('FfAa00', Characteristics.hex, Characteristics.rgb),
        255,
        170,
        0,
      );
    });
    test('bad hex strings are errors', () {
      for (final bad in ['#ff', '#gggggg', '#ffff', '#ffffffff', '']) {
        expect(
          () => cast(bad, Characteristics.hex, Characteristics.rgb),
          throwsConversion(),
        );
      }
      expect(
        () => cast(5, Characteristics.hex, Characteristics.rgb),
        throwsConversion(),
      );
    });
    test('rgb with missing field, non-number or out-of-range channel', () {
      expect(
        () => cast({'r': 1, 'g': 2}, Characteristics.rgb, Characteristics.hex),
        throwsConversion(),
      );
      expect(
        () => cast(
          {'r': 1, 'g': 2, 'b': '3'},
          Characteristics.rgb,
          Characteristics.hex,
        ),
        throwsConversion(),
      );
      expect(
        () => cast(
          {'r': 1, 'g': 2, 'b': 256},
          Characteristics.rgb,
          Characteristics.hex,
        ),
        throwsConversion(),
      );
      expect(
        () => cast(
          {'r': -1, 'g': 2, 'b': 3},
          Characteristics.rgb,
          Characteristics.hex,
        ),
        throwsConversion(),
      );
    });
  });

  // converter/lib/converter/tests/color_test.go
  group('color_test.go', () {
    test('TestRgbToHsb', () {
      final out =
          cast(
                {'r': 54.0, 'g': 94.0, 'b': 169.0},
                Characteristics.rgb,
                Characteristics.hsb,
              )
              as Map;
      expect([out['h'], out['s'], out['b']], [219, 68, 66]);
    });
    test('TestHexToHsb', () {
      final out =
          cast('#365ea9', Characteristics.hex, Characteristics.hsb) as Map;
      expect([out['h'], out['s'], out['b']], [219, 68, 66]);
    });
    test('TestHsbToHex', () {
      expect(
        cast(
          {'h': 219.0, 's': 68.0, 'b': 66.0},
          Characteristics.hsb,
          Characteristics.hex,
        ),
        '#365ea8',
      );
    });
    test('TestHsbToRgb', () {
      final out =
          cast(
                {'h': 219.0, 's': 68.0, 'b': 66.0},
                Characteristics.hsb,
                Characteristics.rgb,
              )
              as Map;
      expect([out['r'], out['g'], out['b']], [54, 94, 168]);
    });

    // go-colorful v1.2.0 Hsv() and Hex(), run on these inputs.
    test('hex to hsb, go-colorful table', () {
      const table = {
        '#ff0000': [0, 100, 100],
        '#00ff00': [120, 100, 100],
        '#0000ff': [240, 100, 100],
        '#808080': [0, 0, 50],
        '#123': [210, 66, 20],
        '#fff': [0, 0, 100],
        '#000': [0, 0, 0],
        '#ffff00': [60, 100, 100],
        '#ab12cd': [289, 91, 80],
        '#7f7f7f': [0, 0, 49],
        '#FFAA00': [40, 100, 100],
        '#642051': [316, 68, 39],
        '#ffffffzz': [0, 0, 100],
      };
      table.forEach((hex, hsb) {
        final out = cast(hex, Characteristics.hex, Characteristics.hsb) as Map;
        expect([out['h'], out['s'], out['b']], hsb, reason: hex);
      });
      expect(
        () => cast('365ea9', Characteristics.hex, Characteristics.hsb),
        throwsConversion(),
      );
      expect(
        () => cast('#fff0', Characteristics.hex, Characteristics.hsb),
        throwsConversion(),
      );
    });
    test('hsb to hex, go-colorful table', () {
      const table = [
        [0.0, 100.0, 100.0, '#ff0000'],
        [120.0, 100.0, 100.0, '#00ff00'],
        [240.0, 50.0, 50.0, '#404080'],
        [359.0, 100.0, 100.0, '#ff0004'],
        [360.0, 100.0, 100.0, '#000000'],
        [219.0, 68.0, 66.0, '#365ea8'],
        [60.0, 0.0, 100.0, '#ffffff'],
        [400.0, 50.0, 50.0, '#404040'],
        [-30.0, 100.0, 100.0, '#000000'],
        [300.0, 25.0, 75.0, '#bf8fbf'],
        [180.0, 100.0, 0.0, '#000000'],
        [45.5, 33.3, 77.7, '#c6b684'],
      ];
      for (final row in table) {
        final out = cast(
          {'h': row[0], 's': row[1], 'b': row[2]},
          Characteristics.hsb,
          Characteristics.hex,
        );
        expect(out, row[3], reason: '$row');
      }
    });
    test('hsb with missing or non-numeric field', () {
      expect(
        () => cast({'h': 1, 's': 2}, Characteristics.hsb, Characteristics.hex),
        throwsConversion(),
      );
      expect(
        () => cast(
          {'h': 1, 's': 2, 'b': 'x'},
          Characteristics.hsb,
          Characteristics.hex,
        ),
        throwsConversion(),
      );
      expect(
        () => cast('x', Characteristics.hsb, Characteristics.hex),
        throwsConversion(),
      );
    });
  });

  // converter/lib/converter/tests/boolean_test.go
  group('boolean_test.go', () {
    test('TestBoolToStatusTrue / False', () {
      expect(
        cast(true, Characteristics.boolean, Characteristics.binaryStatusCode),
        1,
      );
      expect(
        cast(false, Characteristics.boolean, Characteristics.binaryStatusCode),
        0,
      );
      expect(
        cast(true, Characteristics.boolean, Characteristics.binaryStatusCode),
        isA<int>(),
      );
    });
    test('TestStatusToBool 1, 0, 42, -42', () {
      expect(
        cast(1, Characteristics.binaryStatusCode, Characteristics.boolean),
        isTrue,
      );
      expect(
        cast(0, Characteristics.binaryStatusCode, Characteristics.boolean),
        isFalse,
      );
      expect(
        cast(42, Characteristics.binaryStatusCode, Characteristics.boolean),
        isTrue,
      );
      expect(
        cast(-42, Characteristics.binaryStatusCode, Characteristics.boolean),
        isFalse,
      );
    });
    test('non-bool input is an error', () {
      expect(
        () => cast(
          'true',
          Characteristics.boolean,
          Characteristics.binaryStatusCode,
        ),
        throwsConversion(),
      );
      expect(
        () => cast(
          'x',
          Characteristics.binaryStatusCode,
          Characteristics.boolean,
        ),
        throwsConversion(),
      );
    });
  });

  // converter/lib/converter/tests/pressure_test.go
  group('pressure_test.go', () {
    test('TestPressureBarToHPa', () {
      for (final bar in [1, 1.0]) {
        final out = cast(bar, Characteristics.bar, Characteristics.hPa);
        expect(out, isA<double>());
        expect(out, 1000.0);
      }
    });
    test('TestPressureHPaToBar', () {
      for (final hpa in [1000, 1000.0]) {
        final out = cast(hpa, Characteristics.hPa, Characteristics.bar);
        expect(out, isA<double>());
        expect(out, 1.0);
      }
    });
  });

  // converter/lib/converter/tests/speedlevel_test.go
  group('speedlevel_test.go', () {
    const percentToNumber = {0: 1, 3: 1, 20: 2, 77: 7, 100: 10};
    test('TestSpeedlevelPercentToNumber (int and double input)', () {
      percentToNumber.forEach((percent, number) {
        for (final input in [percent, percent.toDouble()]) {
          final out = cast(
            input,
            Characteristics.percentage,
            Characteristics.oneToTen,
          );
          expect(out, isA<int>());
          expect(out, number, reason: '$input');
        }
      });
    });
    test('TestSpeedlevelNumberToPercent (int and double input)', () {
      const numberToPercent = {1: 10, 2: 20, 7: 70, 10: 100};
      numberToPercent.forEach((number, percent) {
        for (final input in [number, number.toDouble()]) {
          final out = cast(
            input,
            Characteristics.oneToTen,
            Characteristics.percentage,
          );
          expect(out, isA<int>());
          expect(out, percent);
        }
      });
    });
    test('non-number input is an error', () {
      expect(
        () => cast('5', Characteristics.percentage, Characteristics.oneToTen),
        throwsConversion(),
      );
      expect(
        () => cast('5', Characteristics.oneToTen, Characteristics.percentage),
        throwsConversion(),
      );
    });
  });

  // converter/lib/converter/tests/lux_test.go and speed_test.go (fuzz seeds)
  group('lux_test.go, speed_test.go', () {
    const seeds = [10.0, 0.0, 2.0, 30.0, -20.0, 2.3, -3.3];
    test('FuzzLux round trip', () {
      for (final orig in seeds) {
        final temp = cast(
          orig,
          Characteristics.lux,
          Characteristics.wattPerSquareMeter,
        );
        final back = cast(
          temp,
          Characteristics.wattPerSquareMeter,
          Characteristics.lux,
        );
        expect(back, closeTo(orig, 0.00001));
      }
    });
    test('FuzzSpeed round trip', () {
      for (final orig in seeds) {
        final temp = cast(
          orig,
          Characteristics.kmh,
          Characteristics.metersPerSecond,
        );
        final back = cast(
          temp,
          Characteristics.metersPerSecond,
          Characteristics.kmh,
        );
        expect(back, closeTo(orig, 0.00001));
      }
    });
  });

  // Edges without a Go test of their own, with the arithmetic of the Go code.
  group('remaining built-in edges', () {
    test('anyclear', () {
      expect(
        cast(true, Characteristics.boolean, Characteristics.anyClear),
        'not clear',
      );
      expect(
        cast(false, Characteristics.boolean, Characteristics.anyClear),
        'clear',
      );
      expect(
        cast('CLEAR', Characteristics.anyClear, Characteristics.boolean),
        isFalse,
      );
      expect(
        cast('smoke', Characteristics.anyClear, Characteristics.boolean),
        isTrue,
      );
      expect(
        () => cast(1, Characteristics.anyClear, Characteristics.boolean),
        throwsConversion(),
      );
    });
    test('carbon monoxide', () {
      expect(
        cast(
          1500,
          Characteristics.microGramPerCubicMeterCO,
          Characteristics.milliGramPerCubicMeterCO,
        ),
        1.5,
      );
      expect(
        cast(
          1.5,
          Characteristics.milliGramPerCubicMeterCO,
          Characteristics.microGramPerCubicMeterCO,
        ),
        1500.0,
      );
      expect(
        cast(
          2,
          Characteristics.ppmCO,
          Characteristics.milliGramPerCubicMeterCO,
        ),
        2 * 1.1642,
      );
      expect(
        cast(
          2.3284,
          Characteristics.milliGramPerCubicMeterCO,
          Characteristics.ppmCO,
        ),
        2.3284 / 1.1642,
      );
    });
    test('kelvin', () {
      expect(
        cast(20, Characteristics.celsius, Characteristics.kelvin),
        closeTo(293.15, 1e-9),
      );
      expect(
        cast(300, Characteristics.kelvin, Characteristics.celsius),
        closeTo(26.85, 1e-9),
      );
    });
    test('kmh and m/s', () {
      expect(
        cast(10, Characteristics.metersPerSecond, Characteristics.kmh),
        36.0,
      );
      expect(
        cast(36, Characteristics.kmh, Characteristics.metersPerSecond),
        10.0,
      );
    });
    test('lux and w/m2', () {
      expect(
        cast(126.7, Characteristics.lux, Characteristics.wattPerSquareMeter),
        1.0,
      );
      expect(
        cast(2, Characteristics.wattPerSquareMeter, Characteristics.lux),
        253.4,
      );
    });
    test('milliseconds, seconds, minutes', () {
      expect(
        cast(120000, Characteristics.milliSeconds, Characteristics.minutes),
        2.0,
      );
      expect(
        cast(2, Characteristics.minutes, Characteristics.milliSeconds),
        120000.0,
      );
      expect(
        cast(1500, Characteristics.milliSeconds, Characteristics.seconds),
        1.5,
      );
      expect(
        cast(1.5, Characteristics.seconds, Characteristics.milliSeconds),
        1500.0,
      );
    });
    test('on/off', () {
      expect(cast(true, Characteristics.boolean, Characteristics.onOff), 'on');
      expect(
        cast(false, Characteristics.boolean, Characteristics.onOff),
        'off',
      );
      expect(
        cast('on', Characteristics.onOff, Characteristics.boolean),
        isTrue,
      );
      expect(
        cast('ON', Characteristics.onOff, Characteristics.boolean),
        isTrue,
      );
      expect(
        cast('On', Characteristics.onOff, Characteristics.boolean),
        isFalse,
      );
      expect(
        cast('off', Characteristics.onOff, Characteristics.boolean),
        isFalse,
      );
    });
    test('zwave contact state', () {
      expect(
        cast(true, Characteristics.boolean, Characteristics.zwaveContactState),
        'Door/Window Closed',
      );
      expect(
        cast(false, Characteristics.boolean, Characteristics.zwaveContactState),
        'Door/Window Open',
      );
      expect(
        cast(
          'Door/Window Open',
          Characteristics.zwaveContactState,
          Characteristics.boolean,
        ),
        isFalse,
      );
      expect(
        cast(
          'Door/Window Closed',
          Characteristics.zwaveContactState,
          Characteristics.boolean,
        ),
        isTrue,
      );
      expect(
        cast(
          'Clear',
          Characteristics.zwaveContactState,
          Characteristics.boolean,
        ),
        isFalse,
      );
      expect(
        () => cast(
          'Tilted',
          Characteristics.zwaveContactState,
          Characteristics.boolean,
        ),
        throwsConversion(),
      );
    });
    test('example characteristics', () {
      final rgb =
          cast('#fff', Characteristics.exampleHex, Characteristics.exampleRgb)
              as Map;
      expect([rgb['r'], rgb['g'], rgb['b']], [255, 255, 255]);
      expect(
        cast(
          {'r': 1, 'g': 2, 'b': 3},
          Characteristics.exampleRgb,
          Characteristics.exampleHex,
        ),
        '#010203',
      );
      expect(
        () =>
            cast('fff', Characteristics.exampleHex, Characteristics.exampleRgb),
        throwsConversion(),
      );
    });
  });

  // Timestamps; expected values from running the Go casts with TZ=UTC.
  group('timestamps', () {
    test('unix seconds, milliseconds and nanoseconds to ISO (UTC)', () {
      expect(
        cast(
          1700000000,
          Characteristics.unixSeconds,
          Characteristics.isoTimestamp,
        ),
        '2023-11-14T22:13:20Z',
      );
      expect(
        cast(
          1700000000123,
          Characteristics.unixMilliSeconds,
          Characteristics.isoTimestamp,
        ),
        '2023-11-14T22:13:20Z',
      );
      expect(
        cast(
          1700000000123456789,
          Characteristics.unixNanoSeconds,
          Characteristics.isoTimestamp,
        ),
        '2023-11-14T22:13:20Z',
      );
      expect(
        cast(
          '1700000000',
          Characteristics.unixSeconds,
          Characteristics.isoTimestamp,
        ),
        '2023-11-14T22:13:20Z',
      );
    });
    test('negative values floor to the earlier second', () {
      expect(
        cast(-1, Characteristics.unixSeconds, Characteristics.isoTimestamp),
        '1969-12-31T23:59:59Z',
      );
      expect(
        cast(
          -1,
          Characteristics.unixMilliSeconds,
          Characteristics.isoTimestamp,
        ),
        '1969-12-31T23:59:59Z',
      );
      expect(
        cast(-1, Characteristics.unixNanoSeconds, Characteristics.isoTimestamp),
        '1969-12-31T23:59:59Z',
      );
    });
    test('ISO to unix, with zone and fraction', () {
      const iso = '2023-11-14T22:13:20.123456789+01:00';
      expect(
        cast(iso, Characteristics.isoTimestamp, Characteristics.unixSeconds),
        1699996400,
      );
      expect(
        cast(
          iso,
          Characteristics.isoTimestamp,
          Characteristics.unixMilliSeconds,
        ),
        1699996400123,
      );
      expect(
        cast(
          iso,
          Characteristics.isoTimestamp,
          Characteristics.unixNanoSeconds,
        ),
        1699996400123456789,
      );
      expect(
        cast(
          '2024-02-29T00:00:00-05:30',
          Characteristics.isoTimestamp,
          Characteristics.unixSeconds,
        ),
        1709184600,
      );
      expect(
        cast(
          '2023-11-14T22:13:20.5Z',
          Characteristics.isoTimestamp,
          Characteristics.unixMilliSeconds,
        ),
        1700000000500,
      );
    });
    test('invalid ISO strings are errors', () {
      for (final bad in [
        '2023-02-29T00:00:00Z',
        '2023-11-14t22:13:20Z',
        '2023-11-14T24:00:00Z',
        '2023-11-14 22:13:20Z',
        '2023-11-14T22:13:20',
        '',
      ]) {
        expect(
          () => cast(
            bad,
            Characteristics.isoTimestamp,
            Characteristics.unixSeconds,
          ),
          throwsConversion(),
          reason: bad,
        );
      }
    });
    test('non-numeric unix input is an error', () {
      expect(
        () => cast(
          '12x',
          Characteristics.unixSeconds,
          Characteristics.isoTimestamp,
        ),
        throwsConversion(),
      );
      expect(
        () => cast(
          true,
          Characteristics.unixSeconds,
          Characteristics.isoTimestamp,
        ),
        throwsConversion(),
      );
    });
    test(
      'multi-hop: UnixSeconds -> UnixNanoSeconds goes through milliseconds',
      () {
        final out = cast(
          1700000000,
          Characteristics.unixSeconds,
          Characteristics.unixNanoSeconds,
        );
        expect(out, 1700000000000000000);
        expect(out, isA<int>());
      },
    );
    test('multi-hop: Seconds -> Minutes goes through milliseconds', () {
      expect(cast(120, Characteristics.seconds, Characteristics.minutes), 2.0);
    });
    test('multi-hop: Hex -> Hsb -> ... and Rgb -> Hsb go through hex', () {
      final out =
          cast(
                {'r': 255, 'g': 0, 'b': 0},
                Characteristics.rgb,
                Characteristics.hsb,
              )
              as Map;
      expect([out['h'], out['s'], out['b']], [0, 100, 100]);
    });
  });

  // converter/lib/converter/tests/extension_function_test.go
  group('extension_function_test.go', () {
    test('TestSNRGY3026', () {
      const formula = '(mapSet(x, "b", (mapGet(x,"b")/100)*254))';
      expect(ext({'b': 23, 'h': 246, 's': 46}, formula), {
        'b': 58.42,
        'h': 246.0,
        's': 46.0,
      });
      expect(ext({'b': 100, 'h': 32, 's': 81}, formula), {
        'b': 254.0,
        'h': 32.0,
        's': 81.0,
      });
      expect(
        converter.convert(
          {'r': 100, 'g': 32, 'b': 81},
          Characteristics.rgb,
          'foo',
          extensions: const [
            ConversionEdge(
              from: Characteristics.hsb,
              to: 'foo',
              distance: -1,
              formula: formula,
              placeholderName: 'x',
            ),
          ],
        ),
        {'b': 99.06, 'h': 316.0, 's': 68.0},
      );
    });

    test('TestExtensionFunctions', () {
      expect(ext('42', 'strlen(x)'), 2);
      expect(ext('42', 'strlen(x)'), isA<int>());
      expect(ext('4.2', 'strIndex(x, ".")'), 1);
      expect(ext('foo:4.2', 'trimPrefix(x, "foo:")'), '4.2');
      expect(ext('foo:4.2', 'trimSuffix(x, ":4.2")'), 'foo');
      expect(ext('foo:4.2', 'replace(x, ":", "/")'), 'foo/4.2');
      expect(ext('0123456789', 'substr(x, 2, 4)'), '23');
      expect(ext('fooBAR', 'toUpperCase(x)'), 'FOOBAR');
      expect(ext('fooBAR', 'toLowerCase(x)'), 'foobar');
      expect(ext('42', 'atoi(x)'), 42);
      expect(ext('42', 'atoi(x)'), isA<int>());
      expect(ext('42.13', 'atof(x)'), 42.13);
      expect(ext(42.13, 'ntoa(x)'), '42.13');
      expect(ext(42, 'ntoa(x)'), '42');
      expect(ext('', 'atof("42.13")'), 42.13);
      expect(ext('', "atoi('42')"), 42);
    });

    test('TestNtoa', () {
      expect(ext(42.0, 'ntoa(x) == "42"'), isTrue);
    });

    test('TestAtoiNtoa', () {
      expect('${ext(42.0, 'atoi(ntoa(x))')}', '42');
    });

    test('TestComplexExpression', () {
      const expr =
          r'(((x-(x%60))/60) >= 10 ? "" : "0") + ntoa(((x-(x%60))/60)) + ":" + (((x%60 >= 10) ? "" : "0" ) + ntoa(x%60))';
      expect(ext(638, expr), '10:38');
      expect(ext(68, expr), '01:08');
    });

    test('TestStructExpression', () {
      const expr =
          r'mapDelete(mapSet(x, "bar", ntoa(mapGet(x, "foo")+1)), "foo")';
      expect(ext({'foo': 42.0}, expr), {'bar': '43'});
    });

    test('TestMapGet (interface, float and string maps)', () {
      expect(ext(<String, dynamic>{'foo': 42.0}, 'mapGet(x, "foo")'), 42.0);
      expect(ext(<String, double>{'foo': 42.0}, 'mapGet(x, "foo")'), 42.0);
      expect(ext(<String, String>{'foo': '42.0'}, 'mapGet(x, "foo")'), '42.0');
    });
  });

  // converter/lib/api/conversions_test.go
  group('conversions_test.go', () {
    test('TestConvertWithGetRequest: hex to rgb', () {
      final out =
          cast('#ff00ff', Characteristics.hex, Characteristics.rgb) as Map;
      expect(jsonEncode(out), '{"r":255,"g":0,"b":255}');
    });
    test('TestConvertWithPostRequest: rgb to hex', () {
      expect(
        cast(
          {'b': 255, 'g': 0, 'r': 255},
          Characteristics.rgb,
          Characteristics.hex,
        ),
        '#ff00ff',
      );
    });
    test('TestPureExtension: two extension hops', () {
      final out = converter.convert(
        13,
        'foo',
        'bar',
        extensions: const [
          ConversionEdge(
            from: 'temp',
            to: 'bar',
            distance: -1,
            formula: 'val - 10',
            placeholderName: 'val',
          ),
          ConversionEdge(
            from: 'foo',
            to: 'temp',
            distance: -1,
            formula: '4*x',
            placeholderName: 'x',
          ),
        ],
      );
      expect(out, 42.0);
    });
    test(
      'TestMixedExtension: extension, built-in Celsius -> Kelvin, extension',
      () {
        final out = converter.convert(
          13,
          'foo',
          'bar',
          extensions: const [
            ConversionEdge(
              from: Characteristics.kelvin,
              to: 'bar',
              distance: -1,
              formula: 'val - 10',
              placeholderName: 'val',
            ),
            ConversionEdge(
              from: 'foo',
              to: Characteristics.celsius,
              distance: -1,
              formula: '4*x',
              placeholderName: 'x',
            ),
          ],
        );
        expect('$out', '315.15');
      },
    );
    test('TestExtensionWithLogic', () {
      expect(ext(true, 'x ? 100 : 0'), 100.0);
      expect(ext(false, 'x ? 100 : 0'), 0.0);
      expect(ext(5, 'x > 2 ? 100 : 0'), 100.0);
      expect(ext(1, 'x > 2 ? 100 : 0'), 0.0);
      expect(ext(1, 'x > 2'), isFalse);
      expect(ext(5, 'x > 2'), isTrue);
    });
  });

  group('LocalConverter behaviour', () {
    test('from == to returns the value unchanged, without cleanup', () {
      final value = {'a': 1};
      expect(identical(cast(value, 'x', 'x'), value), isTrue);
      expect(cast(5, Characteristics.hex, Characteristics.hex), 5);
      expect(cast(double.nan, 'x', 'x'), isNaN);
    });
    test('null stays null', () {
      expect(
        cast(null, Characteristics.celsius, Characteristics.kelvin),
        isNull,
      );
    });
    test('no path is an error', () {
      expect(
        () => cast(1, Characteristics.celsius, Characteristics.rgb),
        throwsConversion(),
      );
      expect(
        () => cast(1, 'unknown-a', Characteristics.celsius),
        throwsConversion(),
      );
      expect(
        () => cast(1, Characteristics.celsius, 'unknown-b'),
        throwsConversion(),
      );
      expect(
        () => cast(1, Characteristics.hex, Characteristics.celsius),
        throwsConversion(),
      );
    });
    test('non-finite numbers fail the input cleanup', () {
      expect(
        () => cast(double.nan, Characteristics.celsius, Characteristics.kelvin),
        throwsConversion(),
      );
      expect(
        () => cast(
          double.infinity,
          Characteristics.celsius,
          Characteristics.kelvin,
        ),
        throwsConversion(),
      );
    });
    test('an unsupported input type fails the input cleanup', () {
      expect(
        () => cast(
          DateTime(2020),
          Characteristics.celsius,
          Characteristics.kelvin,
        ),
        throwsConversion(),
      );
    });
    test('an extension overrides the built-in edge with the same ends', () {
      final out = converter.convert(
        10,
        Characteristics.celsius,
        Characteristics.kelvin,
        extensions: const [
          ConversionEdge(
            from: Characteristics.celsius,
            to: Characteristics.kelvin,
            distance: 0,
            formula: 'x + 273',
            placeholderName: 'x',
          ),
        ],
      );
      expect(out, 283.0);
      expect(
        cast(10, Characteristics.celsius, Characteristics.kelvin),
        closeTo(283.15, 1e-9),
      );
    });
    test(
      'a path of negative extension distances wins over a direct built-in edge',
      () {
        final out = converter.convert(
          10,
          Characteristics.celsius,
          Characteristics.kelvin,
          extensions: const [
            ConversionEdge(
              from: Characteristics.celsius,
              to: 'mid',
              distance: -1,
              formula: 'x * 2',
              placeholderName: 'x',
            ),
            ConversionEdge(
              from: 'mid',
              to: Characteristics.kelvin,
              distance: -1,
              formula: 'x + 1',
              placeholderName: 'x',
            ),
          ],
        );
        expect(out, 21.0);
      },
    );
    test('a negative cycle is reported as an error, not looped on', () {
      expect(
        () => converter.convert(
          5000,
          Characteristics.milliSeconds,
          Characteristics.seconds,
          extensions: const [
            ConversionEdge(
              from: Characteristics.milliSeconds,
              to: Characteristics.minutes,
              distance: -1,
              formula: 'x / 60000',
              placeholderName: 'x',
            ),
          ],
        ),
        throwsConversion(),
      );
    });
    test('the same extension list gives the same result on repeated calls', () {
      const edges = [
        ConversionEdge(
          from: 'a',
          to: 'b',
          distance: 0,
          formula: 'x * 2',
          placeholderName: 'x',
        ),
      ];
      final first = converter.convert(2, 'a', 'b', extensions: edges);
      final second = LocalConverter().convert(
        2,
        'a',
        'b',
        extensions: [
          const ConversionEdge(
            from: 'a',
            to: 'b',
            distance: 0,
            formula: 'x * 2',
            placeholderName: 'x',
          ),
        ],
      );
      expect(first, 4.0);
      expect(converter.convert(3, 'a', 'b', extensions: edges), 6.0);
      expect(second, 4.0);
    });
    test('different extension lists do not leak into each other', () {
      expect(ext(1, 'x + 1', from: 'p', to: 'q'), 2.0);
      expect(ext(1, 'x + 100', from: 'p', to: 'q'), 101.0);
      expect(() => cast(1, 'p', 'q'), throwsConversion());
    });
    test('a bad formula or a failing evaluation is an error', () {
      expect(() => ext(1, 'x +'), throwsConversion());
      expect(() => ext(1, 'y + 1'), throwsConversion());
      expect(() => ext('a', 'x * 2'), throwsConversion());
    });
    test('placeholder name other than x', () {
      expect(ext(4, 'val * 2', placeholder: 'val'), 8.0);
    });
    test('the converter does not alter the caller map', () {
      final input = {'b': 23, 'h': 246, 's': 46};
      ext(input, 'mapSet(x, "b", 1)');
      expect(input, {'b': 23, 'h': 246, 's': 46});
    });
  });

  group('expression operators', () {
    test('arithmetic', () {
      expect(eval('x + 1', 2.0), 3.0);
      expect(eval('x - 1', 2.0), 1.0);
      expect(eval('x * 3', 2.0), 6.0);
      expect(eval('x / 4', 2.0), 0.5);
      expect(eval('x % 3', 7.0), 1.0);
      expect(eval('-7 % 3'), -1.0);
      expect(eval('7 % -3'), 1.0);
      expect(eval('x ** 3', 2.0), 8.0);
      expect(eval('2 ** 3 ** 2'), 64.0);
      expect(eval('10 - 3 - 2'), 5.0);
      expect(eval('1 + 2 * 3'), 7.0);
      expect(eval('(1 + 2) * 3'), 9.0);
      expect(eval('-x ** 2', 3.0), 9.0);
      expect(eval('2 * -x', 3.0), -6.0);
      expect(eval('x / 0', 5.0), double.infinity);
      expect(eval('x % 0', 5.0), isNaN);
    });
    test('numbers are doubles', () {
      expect(eval('1 + 2'), isA<double>());
      expect(eval('.5 + 1'), 1.5);
      expect(eval('5. + 1'), 6.0);
    });
    test('comparisons', () {
      expect(eval('x < 2', 1.0), isTrue);
      expect(eval('x <= 1', 1.0), isTrue);
      expect(eval('x > 2', 1.0), isFalse);
      expect(eval('x >= 1', 1.0), isTrue);
      expect(eval('x == 1', 1.0), isTrue);
      expect(eval('x != 1', 1.0), isFalse);
      expect(eval('"a" < "b"'), isTrue);
      expect(eval('"é" > "z"'), isTrue);
      expect(eval('"abc" >= "abd"'), isFalse);
      expect(() => eval('"a" < 1'), throwsConversion());
    });
    test('logic', () {
      expect(eval('x && true', true), isTrue);
      expect(eval('x || false', false), isFalse);
      expect(eval('!x', true), isFalse);
      expect(eval('false && x', 5.0), isFalse);
      expect(eval('true || x', 5.0), isTrue);
      expect(() => eval('x && true', 5.0), throwsConversion());
      expect(() => eval('x || true', 5.0), throwsConversion());
      expect(() => eval('!x', 5.0), throwsConversion());
    });
    test('ternary and coalesce', () {
      expect(eval('x ? 1 : 2', true), 1.0);
      expect(eval('x ? 1 : 2', false), 2.0);
      expect(eval('x ? 1', false), isNull);
      expect(eval('x ?? 5'), 5.0);
      expect(eval('x ?? 5', 3.0), 3.0);
      expect(() => eval('1 ? 2 : 3'), throwsConversion());
      expect(eval('true ? 1 : x', 5.0), 1.0);
      expect(eval('false ? x : 3', 5.0), 3.0);
      expect(eval('x ? false : true', true), isFalse);
    });
    test('chained ternary groups from the left, as in Go', () {
      expect(eval('false ? 1 : true ? 2 : 3'), 2.0);
      expect(eval('false ? 1 : false ? 2 : 3'), 3.0);
      expect(() => eval('true ? 1 : false ? 2 : 3'), throwsConversion());
      expect(
        () => eval('x == 0 ? "off" : x == 1 ? "on" : "other"', 0.0),
        throwsConversion(),
      );
      expect(eval('x == 0 ? "off" : (x == 1 ? "on" : "other")', 1.0), 'on');
    });
    test('string concatenation uses Go number formatting', () {
      expect(eval('"a" + x', 1000000.0), 'a1e+06');
      expect(eval('"a" + x', 123456.0), 'a123456');
      expect(eval('"a" + x', 1234567.0), 'a1.234567e+06');
      expect(eval('"a" + x', 0.00001), 'a1e-05');
      expect(eval('"a" + x', 0.0001), 'a0.0001');
      expect(eval('"a" + x', -0.5), 'a-0.5');
      expect(eval('"a" + x', true), 'atrue');
      expect(eval('x + "b"', 1.0), '1b');
      expect(eval('"v=" + x', -0.0), 'v=-0');
      expect(eval('"v=" + x', 0.1), 'v=0.1');
      expect(eval('"a" + x', null), 'a<nil>');
      expect(eval('"a" + x', {'b': 1.0, 'a': 2.5}), 'amap[a:2.5 b:1]');
      expect(eval('"a" + x', [1.0, 'b']), 'a[1 b]');
      expect(() => eval('1 + true'), throwsConversion());
    });
    test('ntoa formats without exponent', () {
      expect(eval('ntoa(x)', 1e21), '1000000000000000000000');
      expect(eval('ntoa(x)', 0.000001), '0.000001');
      expect(eval('ntoa(x)', -0.0), '-0');
      expect(eval('ntoa(x)', 1234567.5), '1234567.5');
      expect(eval('ntoa(x + 0.1)', 0.2), '0.30000000000000004');
    });
    test('equality is deep and kind-sensitive', () {
      expect(eval('x == x', {'a': 1.0}), isTrue);
      expect(eval('x != x', [1.0, 2.0]), isFalse);
      expect(eval('1 == "1"'), isFalse);
      expect(eval('atoi("42") == 42'), isFalse);
      expect(eval('atof("3") == 3'), isTrue);
      expect(eval('strlen(x) == 2', 'ab'), isFalse);
      expect(
        eval('mapSet(x, "b", 2) == mapSet(x, "b", 2)', {'a': 1.0}),
        isTrue,
      );
    });
    test('integer function results do not do arithmetic', () {
      expect(() => eval('strlen(x) + 1', 'ab'), throwsConversion());
      expect(() => eval('atoi("12") + 1'), throwsConversion());
      expect(
        () => eval('substr(x, strlen(x) - 2, strlen(x))', 'hello'),
        throwsConversion(),
      );
    });
    test('literals, brackets and quoting', () {
      expect(eval('[x] * 2', 4.0), 8.0);
      expect(eval('"a\\"b"'), 'a"b');
      expect(eval("'a\\'b'"), "a'b");
      expect(() => eval('"it\'s"'), throwsConversion());
      expect(eval('true'), isTrue);
      expect(eval('false'), isFalse);
    });
    test('syntax errors', () {
      for (final bad in [
        '',
        ' ',
        'x +',
        '(x',
        'x)',
        'x y',
        'x 1',
        '1 2',
        'x==-1',
        'x[0]',
        'foo(x)',
        '1e5',
        '0x10',
        '1.5.2',
        'strlen()',
        'strlen("a", )',
        'x ,',
        '- -x',
        '"unclosed',
        'x == nil',
      ]) {
        expect(() => eval(bad, 5.0), throwsConversion(), reason: bad);
      }
    });
  });

  group('unsupported syntax throws', () {
    test('regex, bit operators, in, dates, commas, trailing tokens', () {
      for (final formula in [
        'x =~ "a"',
        'x !~ "a"',
        'x in (1, 2)',
        'x IN (1)',
        '1 & 2',
        '1 | 2',
        '1 ^ 2',
        '1 << 2',
        '1 >> 2',
        '~1',
        '"2014-01-02"',
        '"2014-01-02 15:04"',
        '"2014-01-02T15:04:05Z"',
        '"3:04PM"',
        '"Mon Jan  2 15:04:05 2006"',
        '1, 2',
        '(1, 2)',
        '(1) 2',
      ]) {
        expect(() => eval(formula, 1.0), throwsConversion(), reason: formula);
      }
    });
    test('a string that only resembles a date stays a string', () {
      expect(eval('"12:30"'), '12:30');
      expect(eval('"2014-13-45x"'), '2014-13-45x');
    });
  });

  group('custom functions', () {
    test('substr counts bytes', () {
      expect(eval('substr(x, 1, 3)', 'héllo'), 'é');
      expect(eval('substr(x, 1.9, 3.2)', 'hello'), 'el');
      expect(() => eval('substr(x, 0, 2)', 'héllo'), throwsConversion());
      expect(() => eval('substr(x, 2, 1)', 'hello'), throwsConversion());
      expect(() => eval('substr(x, 0, 9)', 'hello'), throwsConversion());
      expect(() => eval('substr(x, -1, 2)', 'hello'), throwsConversion());
      expect(() => eval('substr(x)', 'hello'), throwsConversion());
      expect(() => eval('substr(x, 0, 1)', 5.0), throwsConversion());
    });
    test('replace', () {
      expect(eval('replace(x, "l", "L")', 'hello'), 'heLLo');
      expect(eval('replace(x, "", "-")', 'abc'), '-a-b-c-');
      expect(() => eval('replace(x, "l")', 'hello'), throwsConversion());
    });
    test('trimSuffix and trimPrefix', () {
      expect(eval('trimSuffix(x, "ghz")', '2.4ghz'), '2.4');
      expect(eval('trimSuffix(x, "")', 'abc'), 'abc');
      expect(eval('trimSuffix(x, "zz")', 'abc'), 'abc');
      expect(eval('trimPrefix(x, "ab")', 'abc'), 'c');
      expect(eval('trimPrefix(x, "zz")', 'abc'), 'abc');
    });
    test('strIndex returns a byte index', () {
      expect(eval('strIndex(x, "l")', 'hello'), 2);
      expect(eval('strIndex(x, "z")', 'hello'), -1);
      expect(eval('strIndex(x, "")', 'hello'), 0);
      expect(eval('strIndex(x, "é")', 'aé'), 1);
      expect(eval('strIndex(x, "l")', 'hello'), isA<int>());
    });
    test('strlen counts bytes', () {
      expect(eval('strlen(x)', 'héllo'), 6);
      expect(eval('strlen(x)', ''), 0);
    });
    test('toUpperCase and toLowerCase', () {
      expect(eval('toUpperCase(x)', 'äbc'), 'ÄBC');
      expect(eval('toLowerCase(x)', 'ÄBC'), 'äbc');
      expect(eval('toUpperCase(x)', 'straße'), 'STRAßE');
    });
    test('atoi', () {
      expect(eval('atoi(x)', '42'), 42);
      expect(eval('atoi(x)', '+42'), 42);
      expect(eval('atoi(x)', '-7'), -7);
      for (final bad in [
        '4_2',
        ' 42',
        '4.2',
        '',
        'x',
        '99999999999999999999',
        '0x10',
      ]) {
        expect(() => eval('atoi(x)', bad), throwsConversion(), reason: bad);
      }
      expect(() => eval('atoi(x)', 4.0), throwsConversion());
    });
    test('atof', () {
      expect(eval('atof(x)', '1e3'), 1000.0);
      expect(eval('atof(x)', '.5'), 0.5);
      expect(eval('atof(x)', '5.'), 5.0);
      expect(eval('atof(x)', '1_0'), 10.0);
      expect(eval('atof(x)', 'inf'), double.infinity);
      expect(eval('atof(x)', '-Infinity'), double.negativeInfinity);
      expect(eval('atof(x)', 'NaN'), isNaN);
      expect(
        eval('atof(trimSuffix(x, "ghz"))*1000000000', '2.4ghz'),
        2400000000.0,
      );
      for (final bad in [' 1', '1e999', '', 'abc', '1__0', '0x1p-2']) {
        expect(() => eval('atof(x)', bad), throwsConversion(), reason: bad);
      }
    });
    test('mapGet', () {
      expect(eval('mapGet(x, "a")', {'a': 1.0}), 1.0);
      expect(() => eval('mapGet(x, "b")', {'a': 1.0}), throwsConversion());
      expect(() => eval('mapGet(x, "a")', 's'), throwsConversion());
      expect(() => eval('mapGet(x, 1)', {'a': 1.0}), throwsConversion());
    });
    test('mapSet and mapDelete return copies', () {
      final original = {'a': 1.0};
      expect(eval('mapSet(x, "b", 2)', original), {'a': 1.0, 'b': 2.0});
      expect(eval('mapDelete(x, "a")', {'a': 1.0, 'b': 2.0}), {'b': 2.0});
      expect(eval('mapDelete(x, "zz")', original), {'a': 1.0});
      expect(original, {'a': 1.0});
    });
    test('ntoa rejects non-numbers', () {
      expect(() => eval('ntoa(x)', 's'), throwsConversion());
      expect(() => eval('ntoa(x)', true), throwsConversion());
    });
    test('the platform formulas', () {
      expect(eval('x * 1.609344', 5.0), 8.04672);
      expect(eval('(x/254)*100', 127.0), 50.0);
      expect(eval('x == "1" || x == "on"', 'on'), isTrue);
      expect(eval('x == "1" || x == "on"', 'off'), isFalse);
      const level = 'x == 0 ? "off" : (x < 16.7 ? "min" : "low")';
      expect(eval(level, 0.0), 'off');
      expect(eval(level, 10.0), 'min');
      expect(eval(level, 20.0), 'low');
    });
  });

  // Rows: formula, parameter as JSON, result kind (d double, i int, s string,
  // b bool, nil, err, unsupported), result text. Produced by running
  // govaluate v3.0.0 with the service's custom functions; "unsupported" rows
  // are where Go evaluates but this port refuses on purpose.
  group('Go probe', () {
    const rows = <(String, String, String, String)>[
      ('x * 1.609344', '5', 'd', '8.04672'),
      ('(x/254)*100', '127', 'd', '50'),
      ('x == "1" || x == "on"', '"on"', 'b', 'true'),
      ('x == "1" || x == "on"', '"1"', 'b', 'true'),
      ('x == "1" || x == "on"', '"off"', 'b', 'false'),
      ('x == 0 ? "off" : (x < 16.7 ? "min" : "low")', '0', 's', 'off'),
      ('x == 0 ? "off" : (x < 16.7 ? "min" : "low")', '10', 's', 'min'),
      ('x == 0 ? "off" : (x < 16.7 ? "min" : "low")', '20', 's', 'low'),
      ('"a" + x', '1000000', 's', 'a1e+06'),
      ('"a" + x', '123456', 's', 'a123456'),
      ('"a" + x', '1234567', 's', 'a1.234567e+06'),
      ('"a" + x', '0.0001', 's', 'a0.0001'),
      ('"a" + x', '0.00001', 's', 'a1e-05'),
      ('"a" + x', '100000', 's', 'a100000'),
      ('"a" + x', '1e21', 's', 'a1e+21'),
      ('"a" + x', '-0.5', 's', 'a-0.5'),
      ('"a" + x', 'true', 's', 'atrue'),
      ('x + 1', '"a"', 's', 'a1'),
      ('x + "b"', 'true', 's', 'trueb'),
      ('ntoa(x)', '1e21', 's', '1000000000000000000000'),
      ('ntoa(x)', '0.000001', 's', '0.000001'),
      ('ntoa(x)', '-0.5', 's', '-0.5'),
      ('ntoa(x)', '42', 's', '42'),
      ('ntoa(x)', '"s"', 'err', ''),
      ('x == -1', '-1', 'b', 'true'),
      ('x==-1', '-1', 'err', ''),
      ('2 * -x', '3', 'd', '-6'),
      ('x ?? 5', 'null', 'd', '5'),
      ('x ?? 5', '3', 'd', '3'),
      ('x ? 1 : 2', 'true', 'd', '1'),
      ('true ? 1 : false ? 2 : 3', '', 'err', ''),
      ('false ? 1 : true ? 2 : 3', '', 'd', '2'),
      ('false ? 1 : false ? 2 : 3', '', 'd', '3'),
      ('true ? false : true', '', 'b', 'false'),
      // Unbracketed chains in concept conversions of the platform (2026-11-09):
      // govaluate errs where the first condition holds and evaluates otherwise.
      ('x == "off" ? 0 : x == "on" ? 1 : x == "dog" ? 2 : 3', '"off"', 'err', ''),
      ('x == "off" ? 0 : x == "on" ? 1 : x == "dog" ? 2 : 3', '"dog"', 'd', '2'),
      ('x == "off" ? 0 : x == "on" ? 1 : x == "dog" ? 2 : 3', '"camp"', 'd', '3'),
      ('x == 0 ? "off" : x == 1 ? "on": x == 2 ? "dog" : "camp"', '1', 'err', ''),
      ('x == 0 ? "off" : x == 1 ? "on": x == 2 ? "dog" : "camp"', '3', 's', 'camp'),
      ('strlen(x) + 1', '"ab"', 'err', ''),
      ('strlen(x) == 2', '"ab"', 'b', 'false'),
      ('atoi(x) == 42', '"42"', 'b', 'false'),
      ('atoi(x)', '"+42"', 'i', '42'),
      ('atoi(x)', '"4_2"', 'err', ''),
      ('atoi(x)', '" 42"', 'err', ''),
      ('atof(x)', '"1e3"', 'd', '1000'),
      ('atof(x)', '"inf"', 'd', '+Inf'),
      ('atof(x)', '" 1"', 'err', ''),
      ('atof(x)', '".5"', 'd', '0.5'),
      ('atof(x)', '"5."', 'd', '5'),
      ('atof(x)', '"0x1p-2"', 'unsupported', ''),
      ('atof(x)', '"1_0"', 'd', '10'),
      ('atof(x)', '"1e999"', 'err', ''),
      ('substr(x, 1, 3)', '"héllo"', 's', 'é'),
      ('substr(x, 0, 2)', '"héllo"', 'unsupported', ''),
      ('substr(x, 2, 1)', '"hello"', 'err', ''),
      ('substr(x, 0, 9)', '"hello"', 'err', ''),
      ('substr(x, -1, 2)', '"hello"', 'err', ''),
      ('substr(x, 1.9, 3.2)', '"hello"', 's', 'el'),
      ('substr(x, strlen(x) - 2, strlen(x))', '"hello"', 'err', ''),
      ('strIndex(x, "l")', '"hello"', 'i', '2'),
      ('strIndex(x, "z")', '"hello"', 'i', '-1'),
      ('strIndex(x, "")', '"hello"', 'i', '0'),
      ('strlen(x)', '"héllo"', 'i', '6'),
      ('toUpperCase(x)', '"straße"', 's', 'STRAßE'),
      ('replace(x, "", "-")', '"abc"', 's', '-a-b-c-'),
      ('replace(x, "l", "L")', '"hello"', 's', 'heLLo'),
      ('mapGet(x, "a")', '{"a":1}', 'd', '1'),
      ('mapGet(x, "b")', '{"a":1}', 'err', ''),
      ('mapGet(x, "a")', '"s"', 'err', ''),
      ('"it\'s"', 'null', 'err', ''),
      ('\'a"b\'', 'null', 'err', ''),
      ('"a\\"b"', 'null', 's', 'a"b'),
      ('\'a\\\'b\'', 'null', 's', 'a\'b'),
      ('x - 1', '5', 'd', '4'),
      ('x % 0', '5', 'd', 'NaN'),
      ('x / 0', '5', 'd', '+Inf'),
      ('-x % 3', '5', 'd', '-2'),
      ('7 % -3', '', 'd', '1'),
      ('-7 % 3', '', 'd', '-1'),
      ('2 ** 0.5', '', 'd', '1.4142135623730951'),
      ('2 ** -1', '', 'd', '0.5'),
      ('(-8) ** (1/3)', '', 'd', 'NaN'),
      ('! x', 'true', 'b', 'false'),
      ('!x', '5', 'err', ''),
      ('x && true', 'true', 'b', 'true'),
      ('x && true', '5', 'err', ''),
      ('false && x', '5', 'b', 'false'),
      ('true || x', '5', 'b', 'true'),
      ('x || true', '5', 'err', ''),
      ('1 < 2 == true', '', 'b', 'true'),
      ('"a" < "b"', '', 'b', 'true'),
      ('"b" < "a"', '', 'b', 'false'),
      ('"a" < 1', '', 'err', ''),
      ('1 == 1', '', 'b', 'true'),
      ('1 == "1"', '', 'b', 'false'),
      ('"a" == "a"', '', 'b', 'true'),
      ('true == true', '', 'b', 'true'),
      ('x == x', '{"a":1}', 'b', 'true'),
      ('x != x', '[1,2]', 'b', 'false'),
      ('x == nil', 'null', 'err', ''),
      ('(1 + 2) * 3', '', 'd', '9'),
      ('1 + 2 * 3', '', 'd', '7'),
      ('10 - 3 - 2', '', 'd', '5'),
      ('2 ** 3 ** 2', '', 'd', '64'),
      ('-x ** 2', '3', 'd', '9'),
      ('1 -1', '', 'd', '0'),
      ('1 - -1', '', 'd', '2'),
      ('1 - (-1)', '', 'd', '2'),
      ('x', 'null', 'nil', ''),
      ('x[0]', '[1,2]', 'err', ''),
      ('[x]', '5', 'd', '5'),
      ('[my var]', '5', 'err', ''),
      ('foo', '5', 'err', ''),
      ('x +', '5', 'err', ''),
      ('(x', '5', 'err', ''),
      ('x)', '5', 'err', ''),
      ('x y', '5', 'err', ''),
      ('x 1', '5', 'err', ''),
      ('1 2', '', 'err', ''),
      ('(1) 2', '', 'unsupported', ''),
      ('true', '', 'b', 'true'),
      ('false', '', 'b', 'false'),
      ('"2014-01-02"', '', 'unsupported', ''),
      ('"12:30"', '', 's', '12:30'),
      ('"3:04PM"', '', 'unsupported', ''),
      ('"2014-01-02 15:04"', '', 'unsupported', ''),
      ('"2014-01-02T15:04:05Z"', '', 'unsupported', ''),
      ('"Mon Jan  2 15:04:05 2006"', '', 'unsupported', ''),
      ('x =~ "a"', '"a"', 'unsupported', ''),
      ('x in (1, 2)', '1', 'unsupported', ''),
      ('1 & 2', '', 'unsupported', ''),
      ('1 << 2', '', 'unsupported', ''),
      ('~1', '', 'unsupported', ''),
      ('x | 1', '1', 'unsupported', ''),
      ('1.5.2', '', 'err', ''),
      ('.5 + 1', '', 'd', '1.5'),
      ('5. + 1', '', 'd', '6'),
      ('1e5', '', 'err', ''),
      ('0x10', '', 'err', ''),
      ('IN', '', 'err', ''),
      ('x IN (1)', '1', 'err', ''),
      ('substr(x)', '"a"', 'err', ''),
      ('strlen()', '', 'err', ''),
      ('strlen(x, x)', '"a"', 'err', ''),
      ('x ? 1', 'true', 'd', '1'),
      ('x ? 1', 'false', 'nil', ''),
      ('1 ? 2 : 3', '', 'err', ''),
      ('true ? 1 : x', '5', 'd', '1'),
      ('false ? x : 3', '5', 'd', '3'),
      ('true ?? x', '5', 'b', 'true'),
      ('strlen("a", )', '', 'err', ''),
      ('x ,', '5', 'err', ''),
      ('1 /* c */', '', 'err', ''),
      ('1 + "2"', '', 's', '12'),
      ('"1" + 2', '', 's', '12'),
      ('"1" + "2"', '', 's', '12'),
      ('1 + true', '', 'err', ''),
      ('true + "a"', '', 's', 'truea'),
      ('x + "a"', '{"b":1,"a":2.5}', 's', 'map[a:2.5 b:1]a'),
      ('x + "a"', '[1,"b"]', 's', '[1 b]a'),
      ('x + "a"', 'null', 's', '<nil>a'),
      ('mapSet(x, "b", 2) == mapSet(x, "b", 2)', '{"a":1}', 'b', 'true'),
      ('atoi("12") + 1', '', 'err', ''),
      ('ntoa(atoi("12"))', '', 's', '12'),
      ('ntoa(strlen("ab"))', '', 's', '2'),
      ('ntoa(atof("1.5"))', '', 's', '1.5'),
      ('atof("3") == 3', '', 'b', 'true'),
      ('atoi(ntoa(x))', '42', 'i', '42'),
      (
        '(((x-(x%60))/60) >= 10 ? "" : "0") + ntoa(((x-(x%60))/60)) + ":" + (((x%60 >= 10) ? "" : "0" ) + ntoa(x%60))',
        '638',
        's',
        '10:38',
      ),
      (
        '(((x-(x%60))/60) >= 10 ? "" : "0") + ntoa(((x-(x%60))/60)) + ":" + (((x%60 >= 10) ? "" : "0" ) + ntoa(x%60))',
        '68',
        's',
        '01:08',
      ),
      ('atof(trimSuffix(x, "ghz"))*1000000000', '"2.4ghz"', 'd', '2.4e+09'),
      ('-x', '4', 'd', '-4'),
      ('-x', '"a"', 'err', ''),
      ('[x] * 2', '4', 'd', '8'),
      ('x * 2 + 1 > 10 && !(x == 3)', '6', 'b', 'true'),
      ('x * 2 + 1 > 10 && !(x == 3)', '3', 'b', 'false'),
      ('x ?? "d"', '"v"', 's', 'v'),
      ('x == 0 ? "off" : x == 1 ? "on" : "other"', '0', 'err', ''),
      ('x == 0 ? "off" : (x == 1 ? "on" : "other")', '1', 's', 'on'),
      ('x > 2 ? 100 : 0', '5', 'd', '100'),
      ('x > 2 ? 100 : 0', '1', 'd', '0'),
      ('x ? 0 : 5', 'true', 'd', '0'),
      ('x ? false : true', 'true', 'b', 'false'),
      ('x > 2', '1', 'b', 'false'),
      ('"abc" >= "abd"', '', 'b', 'false'),
      ('"é" > "z"', '', 'b', 'true'),
      ('1 / 3', '', 'd', '0.3333333333333333'),
      ('0.1 + 0.2', '', 'd', '0.30000000000000004'),
      ('1e3 + 1', '', 'err', ''),
      ('100 * 1.1', '', 'd', '110.00000000000001'),
      ('x * 3.6', '10', 'd', '36'),
      ('x / 3.6', '36', 'd', '10'),
      ('trimSuffix(x, "")', '"abc"', 's', 'abc'),
      ('trimPrefix(x, "ab")', '"abc"', 's', 'c'),
      ('toLowerCase(x)', '"ÄBC"', 's', 'äbc'),
      ('toUpperCase(x)', '"äbc"', 's', 'ÄBC'),
      ('strIndex(x, "é")', '"aé"', 'i', '1'),
      ('ntoa(x + 0.1)', '0.2', 's', '0.30000000000000004'),
      ('ntoa(1234567.5)', '', 's', '1234567.5'),
      ('"v=" + x', '0.1', 's', 'v=0.1'),
    ];
    for (var i = 0; i < rows.length; i++) {
      final (formula, param, kind, text) = rows[i];
      test('#$i $formula  [$param]', () {
        final dynamic x = param.isEmpty ? null : _doubles(jsonDecode(param));
        dynamic run() => eval(formula, x);
        switch (kind) {
          case 'err':
          case 'unsupported':
            expect(run, throwsConversion());
          case 'nil':
            expect(run(), isNull);
          case 'b':
            expect(run(), text == 'true');
          case 's':
            expect(run(), text);
          case 'i':
            final out = run();
            expect(out, isA<int>());
            expect(out, int.parse(text));
          case 'd':
            final out = run();
            expect(out, isA<double>());
            if (text == 'NaN') {
              expect(out, isNaN);
            } else if (text == '+Inf') {
              expect(out, double.infinity);
            } else if (text == '-Inf') {
              expect(out, double.negativeInfinity);
            } else {
              expect(out, double.parse(text));
            }
          default:
            fail('unknown kind $kind');
        }
      });
    }
  });
}
