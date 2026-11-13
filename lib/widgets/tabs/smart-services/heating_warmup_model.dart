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

// Warm-up information of the heating widget: the rows of the heating-warmup operator export and the texts and bar overlays derived from them.

import 'dart:convert';

import 'package:mobile_app/widgets/tabs/smart-services/heating_schedule_editor.dart';
import 'package:mobile_app/widgets/tabs/smart-services/heating_schedule_model.dart';

/// The export columns the widget reads, in the order the query asks for them.
const heatingWarmupColumns = [
  "zone",
  "warmup_minutes",
  "next_start",
  "next_target",
  "next_lead_minutes",
  "windows",
  "measure_station",
  "forecast_station",
  "a",
  "episodes",
];

/// Warm-ups the operator needs before it fits a model.
const heatingWarmupMinEpisodes = 3;

enum HeatingWarmupMode { show, plan }

/// What the info module's `widget_data` says; null without an export id, as in every older instance.
class HeatingWarmupConfig {
  final String exportId;
  final HeatingWarmupMode mode;

  const HeatingWarmupConfig(this.exportId, this.mode);

  static HeatingWarmupConfig? from(dynamic widgetData) {
    final id = widgetData is Map ? widgetData["warmup_export_id"] : null;
    if (id is! String || id.isEmpty) return null;
    return HeatingWarmupConfig(id, widgetData["warmup_mode"] == "plan" ? HeatingWarmupMode.plan : HeatingWarmupMode.show);
  }
}

/// A rising plan boundary of the next 24 hours; [leadMinutes] is null without a model or outdoor temperature.
class HeatingWarmupWindow {
  final DateTime start;
  final double target;
  final int? leadMinutes;

  const HeatingWarmupWindow(this.start, this.target, this.leadMinutes);
}

/// A weather station in use; [own] marks an own outdoor sensor. Name and distance are null while unknown.
class HeatingStation {
  final bool own;
  final String? name;
  final double? distanceKm;

  const HeatingStation({this.own = false, this.name, this.distanceKm});

  static const ownSensor = HeatingStation(own: true);
}

/// The newest export row of one zone.
class HeatingWarmupRow {
  final int? warmupMinutes;
  final DateTime? nextStart;
  final double? nextTarget;
  final int? nextLeadMinutes;
  final List<HeatingWarmupWindow> windows;

  /// Null while unknown, [HeatingStation.ownSensor] for an own outdoor sensor.
  final HeatingStation? measure, forecast;

  final bool hasModel;
  final int? episodes;

  const HeatingWarmupRow({
    this.warmupMinutes,
    this.nextStart,
    this.nextTarget,
    this.nextLeadMinutes,
    this.windows = const [],
    this.measure,
    this.forecast,
    this.hasModel = false,
    this.episodes,
  });
}

int? _int(dynamic v) {
  if (v is int) return v;
  if (v is num && v.isFinite && v == v.roundToDouble()) return v.toInt();
  return null;
}

DateTime? _time(dynamic v) => v is String ? DateTime.tryParse(v)?.toUtc() : null;

/// A JSON column: text of a JSON value, or the value itself. Null for a null column; throws
/// [FormatException] for text that is not JSON.
dynamic _jsonColumn(dynamic v) => v is String ? json.decode(v) : v;

HeatingStation? _station(dynamic column, void Function(String) onError) {
  if (column == null) return HeatingStation.ownSensor;
  try {
    final decoded = _jsonColumn(column);
    if (decoded is! Map) throw const FormatException("not an object");
    final name = decoded["name"], distance = heatingNumber(decoded["distance_km"]);
    return HeatingStation(name: name is String && name.isNotEmpty ? name : null, distanceKm: distance);
  } on FormatException catch (e) {
    onError("Unreadable station of the warm-up export: ${e.message}");
    return null;
  }
}

List<HeatingWarmupWindow> _windows(dynamic column, void Function(String) onError) {
  if (column == null) return const [];
  try {
    final decoded = _jsonColumn(column);
    if (decoded is! List) throw const FormatException("not a list");
    final out = <HeatingWarmupWindow>[];
    for (final w in decoded) {
      final start = w is Map ? _time(w["start"]) : null, target = w is Map ? heatingNumber(w["target"]) : null;
      if (start == null || target == null) continue;
      out.add(HeatingWarmupWindow(start, target, _int(w["lead_minutes"])));
    }
    return out;
  } on FormatException catch (e) {
    onError("Unreadable windows of the warm-up export: ${e.message}");
    return const [];
  }
}

/// One row from its column values by name. An unreadable JSON column is reported through [onError]
/// and left out; the rest of the row stays usable.
HeatingWarmupRow parseHeatingWarmupRow(Map<String, dynamic> values, void Function(String) onError) {
  return HeatingWarmupRow(
    warmupMinutes: _int(values["warmup_minutes"]),
    nextStart: _time(values["next_start"]),
    nextTarget: heatingNumber(values["next_target"]),
    nextLeadMinutes: _int(values["next_lead_minutes"]),
    windows: _windows(values["windows"], onError),
    measure: _station(values["measure_station"], onError),
    forecast: _station(values["forecast_station"], onError),
    hasModel: values["a"] != null,
    episodes: _int(values["episodes"]),
  );
}

/// The row of each zone key from the answers of the per-zone queries, which correspond by index and
/// ask for [heatingWarmupColumns] with limit 1. Each result row starts with the time. A zone
/// without a row is absent from the map.
Map<String, HeatingWarmupRow> heatingWarmupRows(
    List<String> zoneKeys, List<List<List<dynamic>>> results, void Function(String) onError) {
  final out = <String, HeatingWarmupRow>{};
  for (var i = 0; i < zoneKeys.length && i < results.length; i++) {
    if (results[i].isEmpty) continue;
    final row = results[i].first;
    if (row.length != heatingWarmupColumns.length + 1) {
      onError("Unexpected width of a warm-up export row: ${row.length}");
      continue;
    }
    out[zoneKeys[i]] = parseHeatingWarmupRow({for (final (c, name) in heatingWarmupColumns.indexed) name: row[c + 1]}, onError);
  }
  return out;
}

/// "Warming up to 21 °C, about 35 min left" while the room is below the set point; null when the
/// row says nothing about a warm-up in progress.
String? heatingWarmupStatus(HeatingWarmupRow? row, double planned) {
  final minutes = row?.warmupMinutes;
  if (minutes == null) return null;
  if (minutes < 0) return "${formatHeatingTemperature(planned)} is not reachable at this outdoor temperature";
  final left = minutes == 0 ? "almost there" : "about $minutes min left";
  return "Warming up to ${formatHeatingTemperature(planned)}, $left";
}

/// The line about the next rising window, or null without a future window with a lead time.
/// In mode plan it names the heating start, in mode show only the time needed.
String? heatingWarmupNextLine(HeatingWarmupRow? row, HeatingWarmupMode mode, DateTime now) {
  final start = row?.nextStart, target = row?.nextTarget, lead = row?.nextLeadMinutes;
  if (start == null || target == null || lead == null || lead <= 0 || !start.isAfter(now)) return null;
  final temperature = formatHeatingTemperature(target), at = heatingClockText(now, start);
  if (mode == HeatingWarmupMode.show) return "Needs about $lead min to reach $temperature at $at";
  final heatFrom = start.subtract(Duration(minutes: lead));
  if (!heatFrom.isAfter(now)) return "Heating for $temperature at $at";
  return "Heats from ${heatingClockText(now, heatFrom)} for $temperature at $at";
}

/// The muted line while the zone has no model: with the count of warm-ups seen when the row has one.
String? heatingWarmupLearning(HeatingWarmupRow? row) {
  if (row != null && row.hasModel) return null;
  final seen = row?.episodes;
  return seen == null
      ? "Learning the warm-up time"
      : "Learning the warm-up time ($seen of $heatingWarmupMinEpisodes warm-ups seen)";
}

/// "Outdoor: Leipzig (12.3 km) · Forecast: Halle (8.1 km)", or null when nothing is known.
String? heatingStationLine(HeatingStation? measure, HeatingStation? forecast) {
  String? part(String label, HeatingStation? s) {
    if (s == null) return null;
    if (s.own) return "$label: own sensor";
    final name = s.name, km = s.distanceKm;
    if (name == null && km == null) return null;
    final distance = km == null ? null : "${km.toStringAsFixed(1)} km";
    return "$label: ${name == null ? distance : distance == null ? name : "$name ($distance)"}";
  }

  final parts = [part("Outdoor", measure), part("Forecast", forecast)].whereType<String>();
  return parts.isEmpty ? null : parts.join(" · ");
}

/// The warm-up phase of one window on one day row: minutes of the Berlin day, within 0..1440.
class HeatingHatch {
  final int from, to;
  final double temperature;

  const HeatingHatch(this.from, this.to, this.temperature);

  @override
  bool operator ==(Object other) => other is HeatingHatch && other.from == from && other.to == to && other.temperature == temperature;

  @override
  int get hashCode => Object.hash(from, to, temperature);
}

/// The warm-up intervals `[start - lead, start]` that fall on the row of weekday [day] (0 = Monday),
/// which is the next such day from today of [now]. Windows in the past or without a lead are skipped.
List<HeatingHatch> heatingWarmupHatches(List<HeatingWarmupWindow> windows, DateTime now, int day) {
  final today = heatingLocalTime(now);
  final ahead = (day - (today.weekday - 1) + 7) % 7;
  final dayStart = DateTime.utc(today.year, today.month, today.day + ahead);
  final dayEnd = DateTime.utc(today.year, today.month, today.day + ahead + 1);
  final out = <HeatingHatch>[];
  for (final w in windows) {
    final lead = w.leadMinutes;
    if (lead == null || lead <= 0 || !w.start.isAfter(now)) continue;
    final from = heatingLocalTime(w.start.subtract(Duration(minutes: lead))), to = heatingLocalTime(w.start);
    if (!from.isBefore(dayEnd) || !to.isAfter(dayStart)) continue;
    final a = from.isBefore(dayStart) ? 0 : from.difference(dayStart).inMinutes;
    final b = to.isAfter(dayEnd) ? heatingMinutesPerDay : to.difference(dayStart).inMinutes;
    if (b > a) out.add(HeatingHatch(a, b, w.target));
  }
  return out;
}
