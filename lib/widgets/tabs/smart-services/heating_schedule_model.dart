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
import 'dart:ui' show Color;

import 'package:mobile_app/models/content_variable.dart';
import 'package:mobile_app/models/device_command.dart';
import 'package:mobile_app/models/device_command_response.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_type.dart';

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
        "temperature": _jsonNumber(temperature),
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

  /// The latest instant up to [nowUtc] at which the target changed, or null for a constant plan.
  /// Candidates are those of [nextSwitch], looked at backwards over a week and a day.
  HeatingSwitch? lastSwitch(DateTime nowUtc) {
    nowUtc = nowUtc.toUtc();
    final today = heatingLocalTime(nowUtc);
    final candidates = <DateTime>{};
    for (final year in [nowUtc.year - 1, nowUtc.year]) {
      candidates.add(_summerStart(year));
      candidates.add(_summerEnd(year));
    }
    final minutes = {for (final w in windows) ...[w.from, w.to]};
    for (var d = -8; d <= 0; d++) {
      for (final m in minutes) {
        final local = DateTime.utc(today.year, today.month, today.day + d, 0, m);
        candidates.add(local.subtract(const Duration(hours: 1)));
        candidates.add(local.subtract(const Duration(hours: 2)));
      }
    }
    final sorted = candidates.where((c) => !c.isAfter(nowUtc)).toList()..sort((a, b) => b.compareTo(a));
    for (final c in sorted) {
      final t = target(c);
      if (t != target(c.subtract(const Duration(minutes: 1)))) return HeatingSwitch(c, t);
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

  /// A finite number, or a string of one as the process script reads it; null otherwise.
  static double? _number(dynamic v) {
    final n = v is num ? v.toDouble() : (v is String ? double.tryParse(v.trim()) : null);
    return n != null && n.isFinite ? n : null;
  }

  static double _setback(dynamic v) {
    final n = _number(v);
    if (n == null) throw HeatingScheduleException("The setback temperature is not a number: $v");
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
    final t = _number(w["temperature"]);
    if (t == null) throw HeatingScheduleException("Window $n: temperature is not a number");
    return HeatingWindow(days, _minutes(w["from"], n), _minutes(w["to"], n), t);
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

/// Integral values are written without a fraction.
num _jsonNumber(double v) => v == v.roundToDouble() ? v.toInt() : v;

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

/// A thermostat of the `thermostats` parameter; [label] is what the user picked it by.
class HeatingThermostat {
  final String id, label;

  const HeatingThermostat(this.id, this.label);
}

/// The thermostats of the `thermostats` parameter value: a list, or a JSON text of one, whose
/// options are maps or JSON texts of maps `{"device_selection":{"device_id":..},"label":..}`.
/// Options without a device id are skipped and a device counts once, as in the process script.
List<HeatingThermostat> parseHeatingThermostats(dynamic value) {
  try {
    dynamic raw = value;
    if (raw is String) raw = raw.trim().isEmpty ? null : json.decode(raw);
    if (raw == null) return const [];
    if (raw is! List) throw HeatingScheduleException("The thermostats must be a list");
    final out = <HeatingThermostat>[];
    for (var o in raw) {
      if (o is String) o = json.decode(o);
      final selection = o is Map ? o["device_selection"] : null;
      final id = selection is Map ? selection["device_id"] : null;
      if (id is! String || id.isEmpty || out.any((t) => t.id == id)) continue;
      final label = o["label"];
      out.add(HeatingThermostat(id, label is String && label.isNotEmpty ? label : id));
    }
    return out;
  } on FormatException catch (e) {
    throw HeatingScheduleException("The thermostats are not valid JSON: ${e.message}");
  }
}

/// One zone of a stored plan. A null [devices] makes it the rest zone, which takes every selected
/// thermostat no other zone names; a null [setback] means the plan's.
class HeatingZoneDef {
  final String name;
  final List<dynamic>? devices;
  final List<HeatingWindow> windows;
  final double? setback;

  const HeatingZoneDef(this.name, this.devices, this.windows, this.setback);
}

/// A zone with the thermostats it controls; it gets a process of its own. [index] is the position
/// in the stored plan, which also numbers the zone keys of the smart service (`zone:<index>`).
class HeatingZone {
  final String name;
  final List<HeatingThermostat> thermostats;
  final HeatingSchedule schedule;
  final int index;

  const HeatingZone(this.name, this.thermostats, this.schedule, {this.index = 0});

  String get key => "zone:$index";
}

/// The `schedule` parameter: either the legacy shape `{"windows":[..]}` (one zone "Alle" with every
/// thermostat) or `{"zones":[..]}`. Both stay valid; the service reads either.
class HeatingPlan {
  final List<HeatingZoneDef> zones;
  final double setback;

  /// Set by [parse] when the text had the legacy shape.
  final bool legacy;

  static const legacyZoneName = "Alle";

  const HeatingPlan(this.zones, this.setback, {this.legacy = false});

  /// Throws [HeatingScheduleException] when the text or the setback is invalid.
  factory HeatingPlan.parse(String text, dynamic setback) {
    final sb = HeatingSchedule._setback(setback);
    final dynamic decoded;
    try {
      decoded = json.decode(text);
    } on FormatException catch (e) {
      throw HeatingScheduleException("The plan is not valid JSON: ${e.message}");
    }
    final zones = decoded is Map ? decoded["zones"] : null;
    if (zones is List) {
      return HeatingPlan([for (var i = 0; i < zones.length; i++) _zone(zones[i], i + 1)], sb);
    }
    final windows = decoded is Map ? decoded["windows"] : null;
    if (windows is! List) throw HeatingScheduleException("The plan needs a list \"zones\" or \"windows\"");
    final list = [for (var i = 0; i < windows.length; i++) HeatingSchedule._window(windows[i], i + 1)];
    return HeatingPlan([HeatingZoneDef(legacyZoneName, null, list, null)], sb, legacy: true);
  }

  static HeatingZoneDef _zone(dynamic z, int n) {
    if (z is! Map) throw HeatingScheduleException("Zone $n: an object is expected");
    final rawName = z["name"];
    final name = rawName is String && rawName.trim().isNotEmpty ? rawName.trim() : "Zone $n";
    try {
      final windows = z["windows"];
      if (windows is! List) throw HeatingScheduleException("The zone needs a list \"windows\"");
      final devices = z["devices"];
      if (devices != null && devices is! List) throw HeatingScheduleException("The devices must be a list of device ids");
      return HeatingZoneDef(
        name,
        devices as List?,
        [for (var i = 0; i < windows.length; i++) HeatingSchedule._window(windows[i], i + 1)],
        z["setback"] == null ? null : HeatingSchedule._setback(z["setback"]),
      );
    } on HeatingScheduleException catch (e) {
      throw HeatingScheduleException("$name: $e");
    }
  }

  /// One rest zone without an own setback, named "Alle" or not at all, is written as the legacy
  /// shape, which older app versions read; anything else as zones.
  String serialise() {
    final only = zones.length == 1 ? zones.single : null;
    if (only != null && only.devices == null && only.setback == null && (only.name.trim().isEmpty || only.name == legacyZoneName)) {
      return json.encode({"windows": zones.single.windows});
    }
    return json.encode({
      "zones": [
        for (final z in zones)
          {
            "name": z.name,
            if (z.devices != null) "devices": z.devices,
            "windows": z.windows,
            if (z.setback != null) "setback": _jsonNumber(z.setback!),
          }
      ]
    });
  }

  /// What keeps the plan from being saved over [selected], or null: a zone name used twice
  /// (empty names count as "Zone N") or a failing [resolve].
  String? problem(List<HeatingThermostat> selected) {
    final names = [for (final (i, z) in zones.indexed) z.name.trim().isEmpty ? "Zone ${i + 1}" : z.name.trim()];
    if (names.toSet().length != names.length) return "Zone names must be unique.";
    try {
      resolve(selected);
    } on HeatingScheduleException catch (e) {
      return "$e.";
    }
    return null;
  }

  /// The zones that get a process, in plan order, as the process script resolves them. Throws
  /// [HeatingScheduleException] for a device in two zones, a second rest zone, or no zone with a
  /// selected thermostat.
  List<HeatingZone> resolve(List<HeatingThermostat> selected) {
    final taken = <String, String>{};
    var rest = -1;
    final devices = <List<HeatingThermostat>>[];
    for (final (i, z) in zones.indexed) {
      final mine = <HeatingThermostat>[];
      if (z.devices == null) {
        if (rest >= 0) throw HeatingScheduleException("Only one zone may take all other thermostats");
        rest = i;
      } else {
        // Entries that are not text cannot name a thermostat; they are kept but not resolved.
        for (final d in z.devices!.whereType<String>()) {
          final other = taken[d];
          if (other != null) throw HeatingScheduleException("Thermostat $d is in $other and ${z.name}");
          taken[d] = z.name;
          // A device taken out of the selection drops out of its zone.
          final t = selected.where((t) => t.id == d).firstOrNull;
          if (t != null) mine.add(t);
        }
      }
      devices.add(mine);
    }
    if (rest >= 0) devices[rest].addAll(selected.where((t) => !taken.containsKey(t.id)));
    final out = [
      for (final (i, z) in zones.indexed)
        if (devices[i].isNotEmpty) HeatingZone(z.name, devices[i], HeatingSchedule(z.windows, z.setback ?? setback), index: i)
    ];
    if (out.isEmpty) throw HeatingScheduleException("No zone has a selected thermostat");
    return out;
  }
}


const heatingRoomFunctionId = "urn:infai:ses:measuring-function:d19ffeb0-877c-4611-951c-b3fc37d9b9ba";
const heatingBatteryFunctionId = "urn:infai:ses:measuring-function:68dae5ce-a9ee-4487-8872-7943a94e2595";
const heatingAirAspectId = "urn:infai:ses:aspect:a14c5efb-b0b6-46c3-982e-9fded75b5ab6";
const heatingTargetAspectId = "urn:infai:ses:aspect:4f4188b6-f944-45fa-9429-15655f691397";
const heatingReadingAspectId = "urn:infai:ses:aspect:ffcdc0a6-0957-49d7-be9a-af912ecbd3cf";
const heatingCelsiusCharacteristicId = "urn:infai:ses:characteristic:5ba31623-0ccb-4488-bfb7-f73b50e03b5a";
const heatingPercentCharacteristicId = "urn:infai:ses:characteristic:46f808f4-bb9e-4cc2-bd50-dc33ca74f273";

/// Battery level at or below which a thermostat is named in the widget.
const heatingLowBattery = 20.0;

enum HeatingValueKind { room, target, battery }

/// The service of a device type that delivers one [kind] of value, and the aspects to ask it for.
class HeatingValueSource {
  final HeatingValueKind kind;
  final String serviceId;
  final List<String> aspectIds;

  const HeatingValueSource(this.kind, this.serviceId, this.aspectIds);

  String? get aspectId => aspectIds.firstOrNull;

  String get _characteristic => kind == HeatingValueKind.battery ? heatingPercentCharacteristicId : heatingCelsiusCharacteristicId;

  /// The characteristic is asked for explicitly because one device type reports in Kelvin.
  DeviceCommand toCommand(DeviceInstance device) {
    final command = DeviceCommand(functionId, device.id, serviceId, aspectId, null, null, null, _characteristic,
        aspectIds.isEmpty ? null : aspectIds);
    command.deviceInstance = device;
    return command;
  }

  String get functionId => kind == HeatingValueKind.battery ? heatingBatteryFunctionId : heatingRoomFunctionId;
}

ContentVariable? _findVariable(ContentVariable v, String functionId, List<String> aspectIds) {
  if (v.function_id == functionId && aspectIds.every(v.effectiveAspects.contains)) return v;
  for (final sub in v.sub_content_variables ?? const <ContentVariable>[]) {
    final found = _findVariable(sub, functionId, aspectIds);
    if (found != null) return found;
  }
  return null;
}

/// The first service of [type] whose outputs carry the function of [kind], and for the two
/// temperatures a variable with all the aspects that separate room reading from set point (set
/// points carry Air as well). Null when the device type lacks the value.
HeatingValueSource? findHeatingValueSource(DeviceType type, HeatingValueKind kind) {
  final functionId = kind == HeatingValueKind.battery ? heatingBatteryFunctionId : heatingRoomFunctionId;
  final aspectIds = switch (kind) {
    HeatingValueKind.room => [heatingAirAspectId, heatingReadingAspectId],
    HeatingValueKind.target => [heatingTargetAspectId],
    HeatingValueKind.battery => const <String>[],
  };
  for (final service in type.services) {
    for (final output in service.outputs ?? const []) {
      final v = _findVariable(output.content_variable, functionId, aspectIds);
      if (v != null) {
        return HeatingValueSource(kind, service.id, kind == HeatingValueKind.battery ? v.effectiveAspects.take(1).toList() : aspectIds);
      }
    }
  }
  return null;
}

/// What a thermostat reported; a null value is unavailable and left out of the widget.
class HeatingDeviceValues {
  final double? room, target, battery;

  const HeatingDeviceValues({this.room, this.target, this.battery});
}

/// A finite number, or a text of one; null otherwise.
double? heatingNumber(dynamic v) {
  final n = v is num ? v.toDouble() : (v is String ? double.tryParse(v.trim()) : null);
  return n != null && n.isFinite ? n : null;
}

/// Maps the answers of one command batch to values per device. [asked] and [answers] correspond by
/// index; an entry that is not a 200 or not numeric stays unavailable.
Map<String, HeatingDeviceValues> heatingValuesFromAnswers(
    List<(String, HeatingValueKind)> asked, List<DeviceCommandResponse> answers) {
  final found = <String, Map<HeatingValueKind, double>>{};
  for (var i = 0; i < asked.length && i < answers.length; i++) {
    if (answers[i].status_code != 200) continue;
    final n = heatingNumber(answers[i].message);
    if (n != null) (found[asked[i].$1] ??= {})[asked[i].$2] = n;
  }
  return {
    for (final e in found.entries)
      e.key: HeatingDeviceValues(room: e.value[HeatingValueKind.room], target: e.value[HeatingValueKind.target], battery: e.value[HeatingValueKind.battery])
  };
}

/// The mean of the room temperatures present, rounded to one decimal; null when there is none.
double? heatingMeanRoom(Iterable<double?> rooms) {
  final present = rooms.whereType<double>().toList();
  if (present.isEmpty) return null;
  final mean = present.reduce((a, b) => a + b) / present.length;
  return (mean * 10).round() / 10;
}

/// The thermostats of [thermostats] whose battery is at or below [heatingLowBattery], with the level.
List<(HeatingThermostat, double)> heatingLowBatteries(
    List<HeatingThermostat> thermostats, Map<String, HeatingDeviceValues> values) {
  return [
    for (final t in thermostats)
      if (values[t.id]?.battery case final b? when b <= heatingLowBattery) (t, b)
  ];
}

/// A deviation of the device set points from the plan: [temperature] is the common deviating set
/// point or null when they differ, [until] the next switch of the zone or null without one.
class HeatingOverride {
  final double? temperature;
  final DateTime? until;

  const HeatingOverride(this.temperature, this.until);
}

/// Whether someone set a thermostat by hand: a set point differs by at least 0.5 K from the plan,
/// and the last switch lies more than 10 minutes back, because a device needs that long to report
/// the value the plan has just set.
HeatingOverride? heatingManualOverride(HeatingSchedule schedule, Iterable<double> deviceTargets, DateTime now) {
  // Tenths as integers: a difference of 0.5 must not depend on floating-point noise.
  final planned = (schedule.target(now) * 10).round();
  final deviating = {for (final t in deviceTargets) if (((t * 10).round() - planned).abs() >= 5) (t * 10).round()};
  if (deviating.isEmpty) return null;
  final last = schedule.lastSwitch(now);
  if (last != null && now.toUtc().difference(last.at) <= const Duration(minutes: 10)) return null;
  return HeatingOverride(deviating.length == 1 ? deviating.single / 10 : null, schedule.nextSwitch(now)?.at);
}

/// "in 3 h 10 min", "in 25 min", "in under a minute"; null when [d] is more than 24 hours.
String? heatingCountdown(Duration d) {
  if (d > const Duration(hours: 24)) return null;
  if (d < const Duration(minutes: 1)) return "in under a minute";
  final minutes = d.inMinutes;
  if (minutes < 60) return "in $minutes min";
  return minutes % 60 == 0 ? "in ${minutes ~/ 60} h" : "in ${minutes ~/ 60} h ${minutes % 60} min";
}

/// "22:00" of the Berlin clock at [at], with the weekday in front when that is not today of [now].
String heatingClockText(DateTime now, DateTime at) {
  final local = heatingLocalTime(at);
  final today = heatingLocalTime(now);
  final sameDay = local.year == today.year && local.month == today.month && local.day == today.day;
  final time = formatHeatingMinutes(local.hour * 60 + local.minute);
  return sameDay ? time : "${_dayNames[local.weekday - 1]} $time";
}

const _dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

const heatingColdColor = Color(0xFF64B5F6);
const heatingWarmColor = Color(0xFFFF8A3D);
const heatingColdTemperature = 16.0;
const heatingWarmTemperature = 22.0;

/// Blue at 16 degrees and below, orange at 22 and above, linear between; the same scale in the web UI.
Color heatingTemperatureColor(double t) {
  final f = ((t - heatingColdTemperature) / (heatingWarmTemperature - heatingColdTemperature)).clamp(0.0, 1.0);
  return Color.lerp(heatingColdColor, heatingWarmColor, f)!;
}
