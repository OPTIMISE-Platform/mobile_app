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

import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:mobile_app/live/conversion/casts.dart' show Characteristics;
import 'package:mobile_app/models/characteristic.dart';
import 'package:mobile_app/models/content_variable.dart';

/// Colour values as the platform carries them (structures of h/s/b or r/g/b,
/// or a hex string) and their on-screen colours. No I/O, so tests can run it.

enum ColourKind { hsb, rgb, hex }

/// How a colour characteristic is laid out: its [kind] and, for h/s/b, the
/// scale of its brightness and whether h and s are whole numbers.
class ColourFormat {
  final ColourKind kind;
  final double brightnessMax;
  final bool integers;

  const ColourFormat(this.kind, {this.brightnessMax = 100, this.integers = true});
}

/// The format of [c], decided by its structure (sub-characteristics named h, s
/// and b, or r, g and b) or by being the hex characteristic; null for anything
/// else.
ColourFormat? colourFormatOf(Characteristic? c) {
  if (c == null) return null;
  if (c.id == Characteristics.hex) return const ColourFormat(ColourKind.hex);
  if (c.type != ContentVariable.structure) return null;
  final subs = {for (final s in c.sub_characteristics ?? const <Characteristic>[]) s.name: s};
  if (subs.length == 3 && subs.containsKey('r') && subs.containsKey('g') && subs.containsKey('b')) {
    return const ColourFormat(ColourKind.rgb);
  }
  if (subs.length == 3 && subs.containsKey('h') && subs.containsKey('s') && subs.containsKey('b')) {
    final max = subs['b']!.max_value;
    return ColourFormat(ColourKind.hsb,
        brightnessMax: max != null && max.isFinite && max > 0 ? max : 100,
        integers: subs['h']!.type == ContentVariable.integer);
  }
  return null;
}

/// The colour of [value] (any of the three layouts), or null when it is none.
/// An h/s/b value shows its hue and saturation at full value: its brightness
/// is the lamp's own control, and a dim lamp would else show as black.
Color? colourOf(dynamic value) {
  if (value is String) return _parseHex(value);
  if (value is! Map) return null;
  num? at(String key) => value[key] is num ? value[key] as num : null;
  final r = at('r'), g = at('g'), b = at('b');
  if (r != null && g != null && b != null) {
    int ch(num v) => v.round().clamp(0, 255);
    return Color.fromARGB(255, ch(r), ch(g), ch(b));
  }
  final h = at('h'), s = at('s');
  if (h != null && s != null && b != null) {
    return HSVColor.fromAHSV(1, (h % 360).toDouble(), (s / 100).clamp(0, 1).toDouble(), 1).toColor();
  }
  return null;
}

Color? _parseHex(String text) {
  final m = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(text.trim());
  return m == null ? null : Color(0xFF000000 | int.parse(m.group(1)!, radix: 16));
}

/// The hue (degrees) and saturation (0..1) of [value], null when it is no colour.
({double hue, double saturation})? hueSaturationOf(dynamic value) {
  final c = colourOf(value);
  if (c == null) return null;
  final hsv = HSVColor.fromColor(c);
  return (hue: hsv.hue, saturation: hsv.saturation);
}

/// The brightness (0..1) of [value] read in its own layout [format]: b over
/// the format's scale for h/s/b, the HSV value for r/g/b and hex. Null when
/// [value] is not laid out that way, e.g. a lamp in white mode without colour,
/// or when the brightness is 0.
double? colourBrightnessOf(dynamic value, ColourFormat format) {
  switch (format.kind) {
    case ColourKind.hsb:
      if (value is! Map || value['h'] is! num || value['s'] is! num || value['b'] is! num) return null;
      return _nonZero(((value['b'] as num) / format.brightnessMax).clamp(0.0, 1.0).toDouble());
    case ColourKind.rgb:
      if (value is! Map || value['r'] is! num || value['g'] is! num || value['b'] is! num) return null;
      return _nonZero(HSVColor.fromColor(colourOf(value)!).value);
    case ColourKind.hex:
      final c = value is String ? _parseHex(value) : null;
      return c == null ? null : _nonZero(HSVColor.fromColor(c).value);
  }
}

/// A brightness of 0 reads as unknown: a lamp reporting black says nothing
/// about how bright a chosen colour should be.
double? _nonZero(double brightness) => brightness > 0 ? brightness : null;

/// The value to send for hue [hue] and saturation [saturation] (0..1) in
/// [format], at [brightness] (0..1) as b on the format's scale for h/s/b or
/// as the HSV value for r/g/b and hex; null is full brightness. The caller
/// reads [brightness] from the reading in the reading's own layout
/// ([colourBrightnessOf]), so a reading and a control of different layouts
/// or scales keep the lamp as bright as it is.
dynamic colourPayload(double hue, double saturation, ColourFormat format, {double? brightness}) {
  final share = (brightness ?? 1.0).clamp(0.0, 1.0).toDouble();
  switch (format.kind) {
    case ColourKind.hsb:
      // Rounded so a share read back from the same scale gives the same b.
      final b = double.parse((share * format.brightnessMax).toStringAsFixed(6));
      final h = hue % 360, s = saturation.clamp(0, 1) * 100;
      return {
        'h': format.integers ? h.round() : h,
        's': format.integers ? s.round() : s,
        'b': format.integers ? b.round() : b,
      };
    case ColourKind.rgb:
    case ColourKind.hex:
      final c = HSVColor.fromAHSV(1, hue % 360, saturation.clamp(0, 1).toDouble(), share).toColor();
      int ch(double v) => (v * 255).round() & 0xff;
      if (format.kind == ColourKind.rgb) return {'r': ch(c.r), 'g': ch(c.g), 'b': ch(c.b)};
      String hex(int v) => v.toRadixString(16).padLeft(2, '0');
      return '#${hex(ch(c.r))}${hex(ch(c.g))}${hex(ch(c.b))}';
  }
}

/// An approximation of the colour of a black body at [kelvin], for the tone
/// of a white lamp and the track of its temperature slider.
Color kelvinToColour(double kelvin) {
  final t = kelvin.clamp(1000, 40000) / 100;
  double red, green, blue;
  if (t <= 66) {
    red = 255;
    green = 99.4708025861 * math.log(t) - 161.1195681661;
  } else {
    red = 329.698727446 * math.pow(t - 60, -0.1332047592);
    green = 288.1221695283 * math.pow(t - 60, -0.0755148492);
  }
  if (t >= 66) {
    blue = 255;
  } else if (t <= 19) {
    blue = 0;
  } else {
    blue = 138.5177312231 * math.log(t - 10) - 305.0447927307;
  }
  int ch(double v) => v.round().clamp(0, 255);
  return Color.fromARGB(255, ch(red), ch(green), ch(blue));
}
