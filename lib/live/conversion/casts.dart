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

// Port of the built-in casts of the SENERGY converter (40 edges, same ids,
// same distances, same arithmetic). Every cast receives a value that went
// through the converter's input cleanup: numbers are [double], maps and
// lists are rebuilt recursively. Integer branches of the Go code therefore
// never apply; where Go returns an integer type the result is a Dart [int].

import 'dart:math' as math;

import 'expression.dart';

/// Characteristic ids used by the built-in casts.
abstract final class Characteristics {
  static const String anyClear =
      'urn:infai:ses:characteristic:8e520c73-7ee1-4a4b-954b-1c7c55139e27';
  static const String bar =
      'urn:infai:ses:characteristic:2871c1c4-1c8c-4169-81f6-fb5313df08b1';
  static const String binaryStatusCode =
      'urn:infai:ses:characteristic:c0353532-a8fb-4553-a00b-418cb8a80a65';
  static const String boolean =
      'urn:infai:ses:characteristic:7dc1bb7e-b256-408a-a6f9-044dc60fdcf5';
  static const String celsius =
      'urn:infai:ses:characteristic:5ba31623-0ccb-4488-bfb7-f73b50e03b5a';
  static const String exampleBrightness = 'example_brightness';
  static const String exampleHex = 'example_hex';
  static const String exampleLux = 'example_lux';
  static const String exampleRgb = 'example_rgb';
  static const String hPa =
      'urn:infai:ses:characteristic:eb33cf65-b0a2-413d-891d-cada05be01ed';
  static const String hex =
      'urn:infai:ses:characteristic:0fc343ce-4627-4c88-b1e0-d3ed29754af8';
  static const String hsb =
      'urn:infai:ses:characteristic:64928e9f-98ca-42bb-a1e5-adf2a760a2f9';
  static const String hsbB =
      'urn:infai:ses:characteristic:d840607c-c8f9-45d6-b9bd-2c2d444e2899';
  static const String hsbH =
      'urn:infai:ses:characteristic:6ec70e99-8c6a-4909-8d5a-7cc12af76b9a';
  static const String hsbS =
      'urn:infai:ses:characteristic:a66dc568-c0e0-420f-b513-18e8df405538';
  static const String isoTimestamp =
      'urn:infai:ses:characteristic:6bc41b45-a9f3-4d87-9c51-dd3e11257800';
  static const String kelvin =
      'urn:infai:ses:characteristic:75b2d113-1d03-4ef8-977a-8dbcbb31a683';
  static const String kmh =
      'urn:infai:ses:characteristic:becfc22a-7f24-44df-9a46-45acebc56d00';
  static const String kwh =
      'urn:infai:ses:characteristic:3febed55-ba9b-43dc-8709-9c73bae3716e';
  static const String lux =
      'urn:infai:ses:characteristic:0419856b-d198-480e-9998-bf990f226844';
  static const String metersPerSecond =
      'urn:infai:ses:characteristic:04bce19c-839d-45de-8cfb-bd470715f4cd';
  static const String microGramPerCubicMeterCO =
      'urn:infai:ses:characteristic:193ff994-60a4-4ed2-90a1-21b82622cb43';
  static const String milliGramPerCubicMeterCO =
      'urn:infai:ses:characteristic:e4e4fbb3-ef93-4702-b770-44e4186a00b4';
  static const String milliSeconds =
      'urn:infai:ses:characteristic:182e6bb4-8622-453a-9a4d-bfa9c70d6c9c';
  static const String minutes =
      'urn:infai:ses:characteristic:b36eee5d-52f0-4476-a6f7-6dd03b24e0f8';
  static const String onOff =
      'urn:infai:ses:characteristic:7621686a-56bc-402d-b4cc-5b266d39736f';
  static const String oneToTen =
      'urn:infai:ses:characteristic:ac7ad69f-b82e-454a-8b44-5c0440cba787';
  static const String percentage =
      'urn:infai:ses:characteristic:5caa707d-dc08-4f3b-bd9f-f08935c8dd3c';
  static const String ppm =
      'urn:infai:ses:characteristic:9673cd38-8adf-48d0-b9ff-54ab56bbdcf0';
  static const String ppmCO =
      'urn:infai:ses:characteristic:15af5b7b-8b17-4b18-b37e-2e91c839886b';
  static const String rgb =
      'urn:infai:ses:characteristic:5b4eea52-e8e5-4e80-9455-0382f81a1b43';
  static const String rgbB =
      'urn:infai:ses:characteristic:590af9ef-3a5e-4edb-abab-177cb1320b17';
  static const String rgbG =
      'urn:infai:ses:characteristic:5ef27837-4aca-43ad-b8f6-4d95cf9ed99e';
  static const String rgbR =
      'urn:infai:ses:characteristic:dfe6be4a-650c-4411-8d87-062916b48951';
  static const String seconds =
      'urn:infai:ses:characteristic:9e1024da-3b60-4531-9f29-464addccb13c';
  static const String unixMilliSeconds =
      'urn:infai:ses:characteristic:64691f8d-4909-470f-a1fa-e977ebe28684';
  static const String unixNanoSeconds =
      'urn:infai:ses:characteristic:c7dfcb86-2733-4917-a5ca-0a150a458eed';
  static const String unixSeconds =
      'urn:infai:ses:characteristic:8b9411f3-bf56-4e57-8fd4-728bdcd451cd';
  static const String uvIndex =
      'urn:infai:ses:characteristic:0a61343d-c0d1-4af8-9329-3829c30ba59f';
  static const String watt =
      'urn:infai:ses:characteristic:a3931f28-664d-452f-9370-a641fadd21db';
  static const String wattPerSquareMeter =
      'urn:infai:ses:characteristic:a03ef4d9-cee5-4c4c-b797-e813db59dde5';
  static const String zwaveContactState =
      'urn:infai:ses:characteristic:65e9a5db-348f-4888-9d95-588741d67dbf';
}

/// Cost of an edge in the shortest-path search.
const int noLosses = 0;
const int roundingLoss = 1;
const int majorLoss = 20;

typedef CastFunction = dynamic Function(dynamic input);

class CastEdge {
  final String from;
  final String to;
  final int distance;
  final CastFunction cast;

  const CastEdge(this.from, this.to, this.distance, this.cast);
}

// ---------------------------------------------------------------------------
// Helpers

ConversionException _typeError(String what, dynamic v) => ConversionException(
  'unable to interpret value$what; input type is ${_typeName(v)}',
);

String _typeName(dynamic v) {
  if (v == null) return 'nil';
  if (v is double) return 'float64';
  if (v is int) return 'int';
  if (v is String) return 'string';
  if (v is bool) return 'bool';
  if (v is Map) return 'map';
  if (v is List) return 'slice';
  return v.runtimeType.toString();
}

double _number(dynamic v) {
  if (v is num) return v.toDouble();
  throw _typeError('', v);
}

bool _boolean(dynamic v) {
  if (v is bool) return v;
  throw _typeError(' as boolean', v);
}

String _text(dynamic v) {
  if (v is String) return v;
  throw _typeError(' as string', v);
}

/// Go `int64(f)`: truncation. Non-finite values have no integer.
int _toInt64(double d) {
  if (!d.isFinite) {
    throw ConversionException('cannot convert $d to an integer');
  }
  return d.truncate();
}

CastFunction _scale(double Function(double) f) =>
    (input) => f(_number(input));

// ---------------------------------------------------------------------------
// Colours

final RegExp _hexLongRe = RegExp(r'^#[0-9a-fA-F]{6}');
final RegExp _hexShortRe = RegExp(r'^#[0-9a-fA-F]{3}$');
final RegExp _hexStrictRe = RegExp(r'^#(?:[0-9a-f]{3}|[0-9a-f]{6})$');

/// go-playground/colors ParseHEX followed by ToRGB.
Map<String, dynamic> _hexToRgbMap(String hexStr) {
  final hex = hexStr.toLowerCase();
  if (!_hexStrictRe.hasMatch(hex)) {
    throw const ConversionException('color: bad color');
  }
  final int r, g, b;
  if (hex.length == 4) {
    r = int.parse(hex[1], radix: 16) * 17;
    g = int.parse(hex[2], radix: 16) * 17;
    b = int.parse(hex[3], radix: 16) * 17;
  } else {
    r = int.parse(hex.substring(1, 3), radix: 16);
    g = int.parse(hex.substring(3, 5), radix: 16);
    b = int.parse(hex.substring(5, 7), radix: 16);
  }
  return <String, dynamic>{'r': r, 'g': g, 'b': b};
}

/// Reads the channel [key] of an rgb-like map as the Go cast does: it must be
/// present and a number. A value outside 0..255 has no defined uint8 in Go;
/// it is an error here.
int _channel(Map<String, dynamic> m, String key) {
  if (!m.containsKey(key)) throw ConversionException('missing field $key');
  final v = m[key];
  if (v is! double) throw ConversionException('field $key is not a number');
  final i = _toInt64(v);
  if (i < 0 || i > 255) {
    throw ConversionException('field $key is out of range 0..255');
  }
  return i;
}

Map<String, dynamic> _asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  throw const ConversionException(
    'unable to interpret value as map[string]interface{}',
  );
}

String _hexByte(int v) => v.toRadixString(16).padLeft(2, '0');

String _rgbMapToHex(dynamic input) {
  final m = _asMap(input);
  final r = _channel(m, 'r');
  final g = _channel(m, 'g');
  final b = _channel(m, 'b');
  return '#${_hexByte(r)}${_hexByte(g)}${_hexByte(b)}';
}

/// go-colorful Hex(): "#rgb" or "#rrggbb" (anything after six digits is
/// ignored, as fmt.Sscanf does) to floats in 0..1.
(double, double, double) _colorfulHex(String s) {
  if (s.length == 4) {
    if (!_hexShortRe.hasMatch(s)) {
      throw ConversionException('color: $s is not a hex-color');
    }
    const factor = 1.0 / 15.0;
    return (
      int.parse(s[1], radix: 16) * factor,
      int.parse(s[2], radix: 16) * factor,
      int.parse(s[3], radix: 16) * factor,
    );
  }
  if (!_hexLongRe.hasMatch(s)) {
    throw ConversionException('color: $s is not a hex-color');
  }
  const factor = 1.0 / 255.0;
  return (
    int.parse(s.substring(1, 3), radix: 16) * factor,
    int.parse(s.substring(3, 5), radix: 16) * factor,
    int.parse(s.substring(5, 7), radix: 16) * factor,
  );
}

/// go-colorful Color.Hsv(): h in 0..360, s and v in 0..1.
(double, double, double) _toHsv(double r, double g, double b) {
  final min = math.min(math.min(r, g), b);
  final v = math.max(math.max(r, g), b);
  final c = v - min;
  var s = 0.0;
  if (v != 0.0) s = c / v;
  var h = 0.0;
  if (min != v) {
    if (v == r) h = ((g - b) / c).remainder(6.0);
    if (v == g) h = (b - r) / c + 2.0;
    if (v == b) h = (r - g) / c + 4.0;
    h *= 60.0;
    if (h < 0.0) h += 360.0;
  }
  return (h, s, v);
}

/// go-colorful Hsv(h, s, v) followed by Hex().
String _hsvToHex(double hue, double s, double v) {
  final hp = hue / 60.0;
  final c = v * s;
  final x = c * (1.0 - (hp.remainder(2.0) - 1.0).abs());
  final m = v - c;
  var r = 0.0, g = 0.0, b = 0.0;
  if (0.0 <= hp && hp < 1.0) {
    r = c;
    g = x;
  } else if (1.0 <= hp && hp < 2.0) {
    r = x;
    g = c;
  } else if (2.0 <= hp && hp < 3.0) {
    g = c;
    b = x;
  } else if (3.0 <= hp && hp < 4.0) {
    g = x;
    b = c;
  } else if (4.0 <= hp && hp < 5.0) {
    r = x;
    b = c;
  } else if (5.0 <= hp && hp < 6.0) {
    r = c;
    b = x;
  }
  int byte(double channel) {
    final scaled = channel * 255.0 + 0.5;
    if (!(scaled >= 0.0 && scaled < 256.0)) {
      throw const ConversionException('colour channel out of range');
    }
    return scaled.truncate();
  }

  return '#${_hexByte(byte(m + r))}${_hexByte(byte(m + g))}${_hexByte(byte(m + b))}';
}

// ---------------------------------------------------------------------------
// Time

final RegExp _rfc3339Re = RegExp(
  r'^(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)(?:\.(\d+))?(Z|[+-]\d\d:\d\d)$',
);

/// time.Parse(time.RFC3339, s) as (unix seconds, nanoseconds of the second).
(int, int) _parseRfc3339(String s) {
  final m = _rfc3339Re.firstMatch(s);
  if (m == null) {
    throw ConversionException('parsing time "$s" as RFC3339 failed');
  }
  final year = int.parse(m[1]!);
  final month = int.parse(m[2]!);
  final day = int.parse(m[3]!);
  final hour = int.parse(m[4]!);
  final minute = int.parse(m[5]!);
  final second = int.parse(m[6]!);
  if (month < 1 || month > 12 || hour > 23 || minute > 59 || second > 59) {
    throw ConversionException('parsing time "$s": field out of range');
  }
  final date = DateTime.utc(year, month, day, hour, minute, second);
  if (date.month != month || date.day != day) {
    throw ConversionException('parsing time "$s": day out of range');
  }
  var offset = 0;
  final zone = m[8]!;
  if (zone != 'Z') {
    final zh = int.parse(zone.substring(1, 3));
    final zm = int.parse(zone.substring(4, 6));
    if (zh > 24 || zm > 59) {
      throw ConversionException('parsing time "$s": zone offset out of range');
    }
    offset = (zh * 3600 + zm * 60) * (zone[0] == '-' ? -1 : 1);
  }
  var nanos = 0;
  final fraction = m[7];
  if (fraction != null) {
    nanos = int.parse(fraction.padRight(9, '0').substring(0, 9));
  }
  return (date.millisecondsSinceEpoch ~/ 1000 - offset, nanos);
}

/// Seconds since the epoch as RFC3339 in UTC (the Go service runs in UTC).
String _formatRfc3339(int unixSeconds) {
  final DateTime t;
  try {
    t = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000, isUtc: true);
  } on Object {
    throw const ConversionException('timestamp out of range');
  }
  if (t.year < 0 || t.year > 9999) {
    throw const ConversionException('timestamp out of range');
  }
  String p(int v, [int w = 2]) => v.toString().padLeft(w, '0');
  return '${p(t.year, 4)}-${p(t.month)}-${p(t.day)}T${p(t.hour)}:${p(t.minute)}:${p(t.second)}Z';
}

int _floorDiv(int a, int b) {
  final q = a ~/ b;
  return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q;
}

final RegExp _intRe = RegExp(r'^[+-]?\d+$');

/// The numeric input of the unix timestamp casts: a number (truncated) or a
/// decimal string.
int _timestampInput(dynamic v) {
  if (v is num) return _toInt64(v.toDouble());
  if (v is String) {
    final parsed = _intRe.hasMatch(v) ? int.tryParse(v) : null;
    if (parsed == null) {
      throw ConversionException('parsing "$v": invalid syntax or out of range');
    }
    return parsed;
  }
  throw _typeError('', v);
}

// ---------------------------------------------------------------------------
// The 40 edges

final List<CastEdge> builtInCasts = List.unmodifiable([
  // anyclear.go
  CastEdge(
    Characteristics.boolean,
    Characteristics.anyClear,
    noLosses,
    (v) => _boolean(v) ? 'not clear' : 'clear',
  ),
  CastEdge(
    Characteristics.anyClear,
    Characteristics.boolean,
    noLosses,
    (v) => _text(v).toLowerCase() != 'clear',
  ),
  // bar.go (1 bar = 1000 hPa)
  CastEdge(
    Characteristics.hPa,
    Characteristics.bar,
    noLosses,
    _scale((v) => v / 1000.0),
  ),
  CastEdge(
    Characteristics.bar,
    Characteristics.hPa,
    noLosses,
    _scale((v) => v * 1000.0),
  ),
  // binarystatuscode.go
  CastEdge(
    Characteristics.boolean,
    Characteristics.binaryStatusCode,
    noLosses,
    (v) => _boolean(v) ? 1 : 0,
  ),
  CastEdge(
    Characteristics.binaryStatusCode,
    Characteristics.boolean,
    noLosses,
    (v) => _number(v) > 0,
  ),
  // carbonmonoxide.go (ppm factor presumes 20 degC and 1013 mbar)
  CastEdge(
    Characteristics.microGramPerCubicMeterCO,
    Characteristics.milliGramPerCubicMeterCO,
    noLosses,
    _scale((v) => v / 1000),
  ),
  CastEdge(
    Characteristics.milliGramPerCubicMeterCO,
    Characteristics.microGramPerCubicMeterCO,
    noLosses,
    _scale((v) => v * 1000),
  ),
  CastEdge(
    Characteristics.ppmCO,
    Characteristics.milliGramPerCubicMeterCO,
    majorLoss,
    _scale((v) => v * 1.1642),
  ),
  CastEdge(
    Characteristics.milliGramPerCubicMeterCO,
    Characteristics.ppmCO,
    majorLoss,
    _scale((v) => v / 1.1642),
  ),
  // hsb.go
  CastEdge(Characteristics.hex, Characteristics.hsb, roundingLoss, (v) {
    final (r, g, b) = _colorfulHex(_text(v));
    final (h, s, value) = _toHsv(r, g, b);
    return <String, dynamic>{
      'h': _toInt64(h),
      's': _toInt64(s * 100),
      'b': _toInt64(value * 100),
    };
  }),
  CastEdge(Characteristics.hsb, Characteristics.hex, roundingLoss, (v) {
    final m = _asMap(v);
    double field(String key) {
      if (!m.containsKey(key)) throw ConversionException('missing field $key');
      final f = m[key];
      if (f is! double) throw ConversionException('field $key is not a number');
      return f;
    }

    final hue = field('h');
    final saturation = field('s');
    final value = field('b');
    return _hsvToHex(hue, saturation / 100, value / 100);
  }),
  // kelvin.go
  CastEdge(
    Characteristics.celsius,
    Characteristics.kelvin,
    noLosses,
    _scale((v) => v + 273.15),
  ),
  CastEdge(
    Characteristics.kelvin,
    Characteristics.celsius,
    noLosses,
    _scale((v) => v - 273.15),
  ),
  // kmh.go
  CastEdge(
    Characteristics.metersPerSecond,
    Characteristics.kmh,
    roundingLoss,
    _scale((v) => v * 3.6),
  ),
  CastEdge(
    Characteristics.kmh,
    Characteristics.metersPerSecond,
    noLosses,
    _scale((v) => v / 3.6),
  ),
  // lux.go (https://ambientweather.com/faqs/question/view/id/1452/)
  CastEdge(
    Characteristics.lux,
    Characteristics.wattPerSquareMeter,
    majorLoss,
    _scale((v) => v / 126.7),
  ),
  CastEdge(
    Characteristics.wattPerSquareMeter,
    Characteristics.lux,
    majorLoss,
    _scale((v) => v * 126.7),
  ),
  // m.go
  CastEdge(
    Characteristics.milliSeconds,
    Characteristics.minutes,
    roundingLoss,
    _scale((v) => v / 60.0 / 1000.0),
  ),
  CastEdge(
    Characteristics.minutes,
    Characteristics.milliSeconds,
    noLosses,
    _scale((v) => v * 60.0 * 1000.0),
  ),
  // onetoten.go
  CastEdge(Characteristics.percentage, Characteristics.oneToTen, roundingLoss, (
    v,
  ) {
    if (v is! num) {
      throw const ConversionException('unable to interpret in value');
    }
    final level = _toInt64(v.toDouble()) ~/ 10;
    return level < 1 ? 1 : level;
  }),
  CastEdge(Characteristics.oneToTen, Characteristics.percentage, noLosses, (v) {
    if (v is! num) {
      throw const ConversionException(
        'unable to interpret value as characteristic ${Characteristics.oneToTen}',
      );
    }
    return _toInt64(v.toDouble()) * 10;
  }),
  // onoff.go
  CastEdge(
    Characteristics.boolean,
    Characteristics.onOff,
    noLosses,
    (v) => _boolean(v) ? 'on' : 'off',
  ),
  CastEdge(Characteristics.onOff, Characteristics.boolean, noLosses, (v) {
    final s = _text(v);
    return s == 'on' || s == 'ON';
  }),
  // rgb.go
  CastEdge(Characteristics.hex, Characteristics.rgb, noLosses, (v) {
    var s = _text(v);
    if (!s.startsWith('#')) s = '#$s';
    return _hexToRgbMap(s);
  }),
  const CastEdge(
    Characteristics.rgb,
    Characteristics.hex,
    noLosses,
    _rgbMapToHex,
  ),
  // s.go
  CastEdge(
    Characteristics.milliSeconds,
    Characteristics.seconds,
    roundingLoss,
    _scale((v) => v / 1000.0),
  ),
  CastEdge(
    Characteristics.seconds,
    Characteristics.milliSeconds,
    noLosses,
    _scale((v) => v * 1000.0),
  ),
  // unix_timestamp_ms.go
  CastEdge(
    Characteristics.isoTimestamp,
    Characteristics.unixMilliSeconds,
    noLosses,
    (v) {
      final (seconds, nanos) = _parseRfc3339(_text(v));
      return seconds * 1000 + nanos ~/ 1000000;
    },
  ),
  CastEdge(
    Characteristics.unixMilliSeconds,
    Characteristics.isoTimestamp,
    roundingLoss,
    (v) => _formatRfc3339(_floorDiv(_timestampInput(v), 1000)),
  ),
  CastEdge(
    Characteristics.unixMilliSeconds,
    Characteristics.unixNanoSeconds,
    noLosses,
    (v) => _timestampInput(v) * 1000000,
  ),
  // unix_timestamp_ns.go
  CastEdge(
    Characteristics.isoTimestamp,
    Characteristics.unixNanoSeconds,
    noLosses,
    (v) {
      final (seconds, nanos) = _parseRfc3339(_text(v));
      if (seconds.abs() > 9223372035) {
        throw const ConversionException(
          'timestamp out of range for nanoseconds',
        );
      }
      return seconds * 1000000000 + nanos;
    },
  ),
  CastEdge(
    Characteristics.unixNanoSeconds,
    Characteristics.isoTimestamp,
    roundingLoss,
    (v) => _formatRfc3339(_floorDiv(_timestampInput(v), 1000000000)),
  ),
  // unix_timestamp_s.go
  CastEdge(
    Characteristics.isoTimestamp,
    Characteristics.unixSeconds,
    noLosses,
    (v) => _parseRfc3339(_text(v)).$1,
  ),
  CastEdge(
    Characteristics.unixSeconds,
    Characteristics.isoTimestamp,
    roundingLoss,
    (v) => _formatRfc3339(_timestampInput(v)),
  ),
  CastEdge(
    Characteristics.unixSeconds,
    Characteristics.unixMilliSeconds,
    noLosses,
    (v) => _timestampInput(v) * 1000,
  ),
  // zwavecontactstate.go
  CastEdge(
    Characteristics.boolean,
    Characteristics.zwaveContactState,
    noLosses,
    (v) => _boolean(v) ? 'Door/Window Closed' : 'Door/Window Open',
  ),
  CastEdge(
    Characteristics.zwaveContactState,
    Characteristics.boolean,
    noLosses,
    (v) {
      switch (_text(v)) {
        case 'Door/Window Open':
          return false;
        case 'Door/Window Closed':
          return true;
        case 'Clear':
          return false;
        default:
          throw ConversionException("unable to convert '$v' to bool");
      }
    },
  ),
  // example.go (test characteristics of the Go service, kept for parity)
  CastEdge(
    Characteristics.exampleHex,
    Characteristics.exampleRgb,
    10000,
    (v) => _hexToRgbMap(_text(v)),
  ),
  const CastEdge(
    Characteristics.exampleRgb,
    Characteristics.exampleHex,
    10000,
    _rgbMapToHex,
  ),
]);
