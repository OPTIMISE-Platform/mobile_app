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

// Plan logic of the Heizungssteuerung; must match its process script, hence the EU rule for Europe/Berlin.

import 'dart:convert';

/// Name of the release, by which the app recognises the smart service.
const heatingReleaseName = "Heizungssteuerung";

const heatingMinutesPerDay = 1440;

/// A plan or setback the smart service would refuse.
class HeatingScheduleException implements Exception {
  final String message;

  HeatingScheduleException(this.message);

  @override
  String toString() => message;
}

/// [from] and [to] are minutes of the local day; from > to runs past midnight, from == to is the whole day.
class HeatingWindow {
  final List<int> weekdays;
  final int from, to;
  final double temperature;

  const HeatingWindow(this.weekdays, this.from, this.to, this.temperature);

  bool get allDay => from == to;

  HeatingWindow copyWith({List<int>? weekdays, int? from, int? to, double? temperature}) =>
      HeatingWindow(weekdays ?? this.weekdays, from ?? this.from, to ?? this.to, temperature ?? this.temperature);

  Map<String, dynamic> toJson() => {
        "weekdays": weekdays,
        "from": formatHeatingMinutes(from),
        "to": formatHeatingMinutes(to),
        "temperature": temperature == temperature.roundToDouble() ? temperature.toInt() : temperature,
      };

  /// The minute ranges this window covers on weekday [day] (0 = Monday).
  List<(int, int)> _rangesOn(int day) {
    final listed = weekdays.contains(day);
    final before = weekdays.contains((day + 6) % 7);
    if (from == to) return listed ? [(0, heatingMinutesPerDay)] : const [];
    if (from < to) return listed ? [(from, to)] : const [];
    return [
      if (listed) (from, heatingMinutesPerDay),
      if (before) (0, to),
    ];
  }
}

/// A stretch of one weekday with one temperature. [planned] is false for the
/// stretches outside every window, which show the setback.
class HeatingSegment {
  final int from, to;
  final double temperature;
  final bool planned;

  const HeatingSegment(this.from, this.to, this.temperature, this.planned);
}

class HeatingSwitch {
  final DateTime at;
  final double temperature;

  const HeatingSwitch(this.at, this.temperature);
}

class HeatingSchedule {
  final List<HeatingWindow> windows;
  final double setback;

  const HeatingSchedule(this.windows, this.setback);

  static const defaultWindows = [HeatingWindow([0, 1, 2, 3, 4], 360, 1200, 20)];

  /// Throws [HeatingScheduleException] when the schedule text or the setback is invalid.
  factory HeatingSchedule.parse(String text, dynamic setback) {
    final sb = _setback(setback);
    final dynamic decoded;
    try {
      decoded = json.decode(text);
    } on FormatException catch (e) {
      throw HeatingScheduleException("The plan is not valid JSON: ${e.message}");
    }
    final list = decoded is Map ? decoded["windows"] : null;
    if (list is! List) throw HeatingScheduleException("The plan needs a list \"windows\"");
    return HeatingSchedule([for (var i = 0; i < list.length; i++) _window(list[i], i + 1)], sb);
  }

  /// The schedule parameter text: only the keys weekdays, from, to, temperature.
  String serialise() => json.encode({"windows": windows});

  /// The temperature that applies at the instant [utc].
  double target(DateTime utc) {
    final local = heatingLocalTime(utc);
    return _targetAt(local.weekday - 1, local.hour * 60 + local.minute);
  }

  /// The first instant after [nowUtc] with a different target, or null for a
  /// constant plan. Candidates are the window boundaries of the local days 0..8
  /// with both Berlin offsets and the clock changes of this and the next year.
  HeatingSwitch? nextSwitch(DateTime nowUtc) {
    nowUtc = nowUtc.toUtc();
    final current = target(nowUtc);
    final today = heatingLocalTime(nowUtc);
    final candidates = <DateTime>{};
    for (final year in [nowUtc.year, nowUtc.year + 1]) {
      candidates.add(_summerStart(year));
      candidates.add(_summerEnd(year));
    }
    final minutes = {for (final w in windows) ...[w.from, w.to]};
    for (var d = 0; d <= 8; d++) {
      for (final m in minutes) {
        final local = DateTime.utc(today.year, today.month, today.day + d, 0, m);
        candidates.add(local.subtract(const Duration(hours: 1)));
        candidates.add(local.subtract(const Duration(hours: 2)));
      }
    }
    final sorted = candidates.where((c) => c.isAfter(nowUtc)).toList()..sort();
    for (final c in sorted) {
      final t = target(c);
      if (t != current) return HeatingSwitch(c, t);
    }
    return null;
  }

  /// The segments of weekday [day] (0 = Monday), from 0 to 1440 without gaps.
  List<HeatingSegment> segmentsOf(int day) {
    final cuts = <int>{0, heatingMinutesPerDay};
    for (final w in windows) {
      for (final (a, b) in w._rangesOn(day)) {
        cuts..add(a)..add(b);
      }
    }
    final points = cuts.toList()..sort();
    final segments = <HeatingSegment>[];
    for (var i = 0; i + 1 < points.length; i++) {
      final from = points[i], to = points[i + 1];
      final covering = _coveringAt(day, from);
      final seg = HeatingSegment(from, to, covering ?? setback, covering != null);
      final last = segments.isEmpty ? null : segments.last;
      if (last != null && last.temperature == seg.temperature && last.planned == seg.planned) {
        segments[segments.length - 1] = HeatingSegment(last.from, to, last.temperature, last.planned);
      } else {
        segments.add(seg);
      }
    }
    return segments;
  }

  double? _coveringAt(int day, int minute) {
    double? best;
    for (final w in windows) {
      for (final (a, b) in w._rangesOn(day)) {
        if (minute >= a && minute < b && (best == null || w.temperature > best)) best = w.temperature;
      }
    }
    return best;
  }

  double _targetAt(int day, int minute) => _coveringAt(day, minute) ?? setback;

  static double _setback(dynamic v) {
    final n = v is num ? v.toDouble() : (v is String ? double.tryParse(v.trim()) : null);
    if (n == null || !n.isFinite) throw HeatingScheduleException("The setback temperature is not a number: $v");
    return n;
  }

  static HeatingWindow _window(dynamic w, int n) {
    if (w is! Map) throw HeatingScheduleException("Window $n: an object is expected");
    final rawDays = w["weekdays"];
    final List<int> days;
    if (rawDays == null || (rawDays is List && rawDays.isEmpty)) {
      days = [0, 1, 2, 3, 4, 5, 6];
    } else if (rawDays is List) {
      days = [
        for (final d in rawDays)
          if (d is int && d >= 0 && d <= 6) d else throw HeatingScheduleException("Window $n: weekday 0 (Monday) to 6 (Sunday) expected, not $d")
      ];
    } else {
      throw HeatingScheduleException("Window $n: weekdays must be a list");
    }
    final t = w["temperature"];
    if (t is! num || !t.isFinite) throw HeatingScheduleException("Window $n: temperature is not a number");
    return HeatingWindow(days, _minutes(w["from"], n), _minutes(w["to"], n), t.toDouble());
  }

  static final _time = RegExp(r'^(\d{1,2}):(\d{2})$');

  static int _minutes(dynamic v, int n) {
    final m = v is String ? _time.firstMatch(v) : null;
    if (m != null) {
      final h = int.parse(m[1]!), min = int.parse(m[2]!);
      if (min < 60 && (h < 24 || (h == 24 && min == 0))) return h * 60 + min;
    }
    throw HeatingScheduleException("Window $n: time hh:mm expected, not $v");
  }
}

/// "HH:MM" of a minute of the day; 1440 is "24:00".
String formatHeatingMinutes(int minutes) =>
    "${(minutes ~/ 60).toString().padLeft(2, "0")}:${(minutes % 60).toString().padLeft(2, "0")}";

DateTime _lastSunday(int year, int month) {
  final last = DateTime.utc(year, month + 1, 0);
  return DateTime.utc(year, month, last.day - last.weekday % 7, 1);
}

DateTime _summerStart(int year) => _lastSunday(year, 3);

DateTime _summerEnd(int year) => _lastSunday(year, 10);

/// The offset of Europe/Berlin to UTC at [utc]: two hours from the last Sunday
/// of March 01:00 UTC until the last Sunday of October 01:00 UTC, else one.
Duration heatingOffset(DateTime utc) {
  utc = utc.toUtc();
  final summer = !utc.isBefore(_summerStart(utc.year)) && utc.isBefore(_summerEnd(utc.year));
  return Duration(hours: summer ? 2 : 1);
}

/// The Berlin wall clock at [utc], as a DateTime whose UTC fields carry it.
/// Weekday: Monday is 1 as in DateTime.
DateTime heatingLocalTime(DateTime utc) => utc.toUtc().add(heatingOffset(utc));
