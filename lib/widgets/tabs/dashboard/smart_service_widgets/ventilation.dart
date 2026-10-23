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

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:mobile_app/models/exception_log_element.dart';
import 'package:mobile_app/shared/dio_status.dart';
import 'package:mobile_app/shared/display_time.dart';
import 'package:mobile_app/shared/formats.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/tabs/dashboard/dashboard.dart' show heightUnit;
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/shared/request.dart';

/// What ventilating does for one indoor sensor, as the process decided it.
enum VentilationRoomState { helps, noBenefit, missing }

double? _number(dynamic value) => value is num ? value.toDouble() : null;

/// A relative humidity in percent, clamped to 0..100 so a stray value cannot
/// show a figure the sensor cannot produce.
double? _humidity(dynamic value) => _number(value)?.clamp(0.0, 100.0).toDouble();

class VentilationOutdoor {
  const VentilationOutdoor({this.t, this.rh, required this.valid});

  final double? t;
  final double? rh;

  /// Whether the outdoor sensor delivered a usable reading. The figures are
  /// not shown otherwise.
  final bool valid;

  static VentilationOutdoor? fromJson(dynamic json) {
    if (json is! Map) return null;
    return VentilationOutdoor(
      t: _number(json["t"]),
      rh: _humidity(json["rh"]),
      valid: json["valid"] == true,
    );
  }
}

class VentilationRoom {
  const VentilationRoom({required this.name, required this.state, this.rh, this.rhAfter});

  final String name;
  final VentilationRoomState state;

  /// Humidity now, 0..100. Null for a missing room.
  final double? rh;

  /// Humidity after ventilating, 0..100. Null for a missing room.
  final double? rhAfter;

  /// Null when the entry is not a map. A room whose state is helps or
  /// no_benefit but lacks a humidity figure is taken as missing, because the
  /// row has nothing to show for it.
  static VentilationRoom? fromJson(dynamic json) {
    if (json is! Map) return null;
    final name = json["name"] is String ? json["name"] as String : "";
    final state = switch (json["state"]) {
      "helps" => VentilationRoomState.helps,
      "no_benefit" => VentilationRoomState.noBenefit,
      _ => VentilationRoomState.missing,
    };
    final rh = _humidity(json["rh"]);
    final rhAfter = _humidity(json["rh_after"]);
    if (state == VentilationRoomState.missing || rh == null || rhAfter == null) {
      return VentilationRoom(name: name, state: VentilationRoomState.missing);
    }
    return VentilationRoom(name: name, state: state, rh: rh, rhAfter: rhAfter);
  }
}

class VentilationState {
  const VentilationState({this.updatedAt, this.outdoor, this.rooms = const [], this.threshold});

  /// Set only when the response is the envelope `{key, value, updated_at}`.
  final DateTime? updatedAt;
  final VentilationOutdoor? outdoor;
  final List<VentilationRoom> rooms;

  /// Humidity above which the process notifies, when notifications are on.
  final double? threshold;

  /// Reads either the envelope (`value` is a map) or the bare state object.
  /// Null when the body is not a map, or when it carries neither `outdoor`
  /// nor `rooms`.
  static VentilationState? fromJson(dynamic body) {
    if (body is! Map) return null;
    final envelope = body["value"] is Map;
    final value = envelope ? body["value"] as Map : body;
    final outdoor = VentilationOutdoor.fromJson(value["outdoor"]);
    final rawRooms = value["rooms"];
    if (outdoor == null && rawRooms is! List) return null;
    final rooms = rawRooms is List
        ? [
            for (final r in rawRooms)
              if (VentilationRoom.fromJson(r) case final room?) room
          ]
        : const <VentilationRoom>[];
    final updatedAt = body["updated_at"];
    return VentilationState(
      updatedAt: envelope && updatedAt is String ? DateTime.tryParse(updatedAt) : null,
      outdoor: outdoor,
      rooms: rooms,
      threshold: _number(value["threshold"]),
    );
  }
}

/// Labels from the widget data. Each one is optional and falls back to the
/// English default.
class VentilationLabels {
  const VentilationLabels({
    this.title = "Ventilation",
    this.helps = "Ventilating helps",
    this.noBenefit = "Ventilating does not help",
    this.missing = "Reading missing",
    this.outside = "Outside",
    this.updated = "As of",
  });

  final String title;
  final String helps;
  final String noBenefit;
  final String missing;
  final String outside;
  final String updated;

  factory VentilationLabels.fromJson(dynamic json) {
    if (json is! Map) return const VentilationLabels();
    String pick(String key, String fallback) => json[key] is String ? json[key] as String : fallback;
    const defaults = VentilationLabels();
    return VentilationLabels(
      title: pick("title", defaults.title),
      helps: pick("helps", defaults.helps),
      noBenefit: pick("no_benefit", defaults.noBenefit),
      missing: pick("missing", defaults.missing),
      outside: pick("outside", defaults.outside),
      updated: pick("updated", defaults.updated),
    );
  }
}

// Fixed heights, so the widget height computed from the room count matches
// what the rows draw.
const double _headerHeight = 24 + Spacing.xxs + 20 + Spacing.md;
const double _roomRowHeight = 48;
const double _dividerHeight = 1;
// The dashboard card has no padding of its own (dashboard.dart).
const double _padding = Spacing.md;
// The rows have fixed heights; larger text would overflow them.
const double _maxTextScale = 1.3;

class SmSeVentilation extends SmSeRequest {
  @override
  setPreview(bool enabled) => null;

  @override
  double width = 5;

  VentilationState? _state;
  VentilationLabels _labels = const VentilationLabels();

  @override
  double get height {
    final state = _state;
    // Room for the "No Data" text.
    if (state == null) return 3;
    final rows = state.rooms.length;
    final pixels = 2 * _padding +
        _headerHeight +
        rows * _roomRowHeight +
        (rows > 0 ? (rows - 1) * _dividerHeight : 0);
    return (pixels / heightUnit).ceilToDouble();
  }

  @override
  Future<void> configure(dynamic data) async {
    await super.configure(data);
    if (data is Map<String, dynamic>) {
      _labels = VentilationLabels.fromJson(data["labels"]);
    }
  }

  @override
  Widget buildInternal(BuildContext context, bool parentFlexible) {
    final state = _state;
    final Widget w = state == null
        ? const Center(child: Text("No Data"))
        : MediaQuery.withClampedTextScaling(
            maxScaleFactor: _maxTextScale,
            child: Padding(
              padding: const EdgeInsets.all(_padding),
              child: _VentilationView(state: state, labels: _labels),
            ),
          );
    return parentFlexible ? Expanded(child: w) : w;
  }

  @override
  Future<void> refreshInternal() async {
    _state = null;
    final Response<dynamic> resp;
    try {
      resp = await request.perform<dynamic>();
    } on DioException catch (e) {
      // Non-2xx and bodies Dio cannot decode show "No Data" here, not the
      // toast that refresh() raises for other failures.
      ExceptionLogElement.Log(e.toString());
      return;
    }
    if (!isSuccessStatus(resp.statusCode)) return;
    _state = VentilationState.fromJson(resp.data);
  }
}

class _VentilationView extends StatelessWidget {
  const _VentilationView({required this.state, required this.labels});

  final VentilationState state;
  final VentilationLabels labels;

  String get _outdoorLine {
    final outdoor = state.outdoor;
    if (outdoor == null) return "";
    if (!outdoor.valid) return "${labels.outside}: ${labels.missing}";
    final figures = [
      if (outdoor.valid && outdoor.t != null) "${outdoor.t!.toStringAsFixed(1)} °C",
      if (outdoor.valid && outdoor.rh != null) _percent(outdoor.rh!),
    ].join(" · ");
    return figures.isEmpty ? labels.outside : "${labels.outside} $figures";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final updatedAt = state.updatedAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 24,
          child: Row(children: [
            Expanded(
              child: Text(labels.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(color: scheme.onSurface)),
            ),
            if (updatedAt != null)
              Text("${labels.updated} ${Formats.hhmm.format(toDisplayTime(updatedAt))}",
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ]),
        ),
        const SizedBox(height: Spacing.xxs),
        SizedBox(
          height: 20,
          child: Text(_outdoorLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: state.outdoor?.valid == false ? context.appColors.warnInk : scheme.onSurfaceVariant)),
        ),
        const SizedBox(height: Spacing.md),
        for (var i = 0; i < state.rooms.length; i++) ...[
          if (i > 0)
            Divider(height: _dividerHeight, thickness: _dividerHeight, color: scheme.outlineVariant),
          SizedBox(
            height: _roomRowHeight,
            child: _RoomRow(room: state.rooms[i], labels: labels),
          ),
        ],
      ],
    );
  }
}

String _percent(double value) => "${value.round()} %";

class _RoomRow extends StatelessWidget {
  const _RoomRow({required this.room, required this.labels});

  final VentilationRoom room;
  final VentilationLabels labels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final appColors = context.appColors;
    final (color, icon, status) = switch (room.state) {
      VentilationRoomState.helps => (appColors.appInk, Icons.air, labels.helps),
      VentilationRoomState.noBenefit => (scheme.onSurfaceVariant, Icons.air, labels.noBenefit),
      VentilationRoomState.missing => (appColors.warnInk, Icons.sensors_off, labels.missing),
    };
    final hasValues = room.state != VentilationRoomState.missing;
    final figureStyle = theme.textTheme.titleLarge?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Row(children: [
      Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.15),
        ),
        child: Icon(icon, size: 14, color: color),
      ),
      const SizedBox(width: Spacing.md),
      Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(room.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(color: scheme.onSurface)),
            Text(status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: color)),
          ],
        ),
      ),
      if (hasValues) ...[
        const SizedBox(width: Spacing.sm),
        Text(_percent(room.rh!), style: figureStyle?.copyWith(color: scheme.onSurface)),
        const SizedBox(width: Spacing.xxs),
        Icon(Icons.arrow_forward_rounded, size: 20, color: color),
        const SizedBox(width: Spacing.xxs),
        Text(_percent(room.rhAfter!),
            style: figureStyle?.copyWith(color: color, fontWeight: FontWeight.w600)),
      ],
    ]);
  }
}
