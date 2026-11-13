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

// Dashboard widget of the Heizungssteuerung: per zone the measured and planned temperature, next switch point, today and the week.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:mobile_app/exceptions/unexpected_status_code_exception.dart';
import 'package:mobile_app/models/db_query.dart';
import 'package:mobile_app/models/device_command.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/smart_service.dart';
import 'package:mobile_app/services/db_query.dart';
import 'package:mobile_app/services/device_commands.dart';
import 'package:mobile_app/services/device_types.dart';
import 'package:mobile_app/services/devices.dart';
import 'package:mobile_app/services/smart_service.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/toast.dart';
import 'package:mobile_app/widgets/tabs/dashboard/dashboard.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/base.dart';
import 'package:mobile_app/widgets/tabs/smart-services/heating_schedule_editor.dart';
import 'package:mobile_app/widgets/tabs/smart-services/heating_schedule_model.dart';
import 'package:mobile_app/widgets/tabs/smart-services/automation_suggestions_load.dart' show exportHasNoTable;
import 'package:mobile_app/widgets/tabs/smart-services/heating_warmup_model.dart';
import 'package:mobile_app/widgets/tabs/smart-services/heating_zone_editor.dart';
import 'package:mobile_app/widgets/tabs/smart-services/instance_parameters.dart';

/// How often the thermostat values are read again; the plan is read on load only.
const heatingValuesInterval = Duration(minutes: 5);

class SmSeHeatingSchedule extends SmartServiceModuleWidget {
  static const _messageUnits = 3.0;

  // Pixel heights of the parts of the body; [height] adds them up to grid units.
  static const _framePx = 100.0; // padding, header row, legend and edit row
  static const _namedHeaderPx = 36.0;
  static const _bigRowPx = 40.0;
  static const _nextRowPx = 20.0;
  static const _manualPx = 32.0; // the status row with the manual and warm-up pills
  static const _warmupLinePx = 20.0;
  static const _batteryPx = 20.0;
  static const _gapPx = 8.0;
  static const _axisPx = 16.0;
  static const _dayRowPx = 22.0;
  static const _toggleRowPx = 32.0;

  SmartServiceInstance? _instance;
  HeatingPlan? _plan;
  List<HeatingThermostat> _thermostats = const [];
  List<HeatingZone>? _zones;
  String? _error;

  /// The stored schedule text when it cannot be read, so the user sees what is there.
  String? _raw;

  /// What the thermostats reported, by device id; empty while unknown or when reading failed.
  Map<String, HeatingDeviceValues> _values = const {};

  /// Set when the instance has a warm-up export; null for every older instance.
  HeatingWarmupConfig? _warmup;

  /// The newest export row per zone key; null while unknown or when reading failed.
  Map<String, HeatingWarmupRow>? _warmupRows;

  List<DeviceCommand>? _commands;
  List<(String, HeatingValueKind)> _asked = const [];

  /// Zones whose week the user opened or closed, by zone name; the default depends on the zone count.
  final Map<String, bool> _weekOpen = {};

  DashboardState? _dashboard;
  Timer? _valuesTimer;

  @override
  setPreview(bool enabled) => null;

  @override
  double width = 1;

  @override
  Future<void> configure(dynamic data) async {
    _warmup = HeatingWarmupConfig.from(data);
  }

  bool _weekExpanded(HeatingZone zone) => _weekOpen[zone.name] ?? _zones!.length == 1;

  HeatingOverride? _override(HeatingZone zone, DateTime now) {
    final targets = [for (final t in zone.thermostats) ?_values[t.id]?.target];
    return heatingManualOverride(zone.schedule, targets, now);
  }

  HeatingWarmupRow? _warmupRow(HeatingZone zone) => _warmupRows?[zone.key];

  String? _warmupStatus(HeatingZone zone, DateTime now) =>
      _warmup == null ? null : heatingWarmupStatus(_warmupRow(zone), zone.schedule.target(now));

  String? _warmupNextLine(HeatingZone zone, DateTime now) =>
      _warmup == null ? null : heatingWarmupNextLine(_warmupRow(zone), _warmup!.mode, now);

  /// Only when the export was read: without information the widget looks as before.
  String? _warmupLearning(HeatingZone zone) => _warmupRows == null ? null : heatingWarmupLearning(_warmupRow(zone));

  /// The stations are the same in every zone's row, so the first row that names them speaks for the instance.
  String? _stationLine() {
    final rows = _warmupRows;
    if (_zones == null || rows == null) return null;
    for (final zone in _zones!) {
      final row = rows[zone.key];
      if (row != null) return heatingStationLine(row.measure, row.forecast);
    }
    return null;
  }

  @override
  double get height {
    final zones = _zones;
    if (zones == null) return _plan == null ? _messageUnits : _messageUnits + 1;
    final now = DateTime.now().toUtc();
    var px = _framePx;
    for (final zone in zones) {
      px += _bigRowPx + _nextRowPx + _gapPx + _axisPx + _dayRowPx + _toggleRowPx + _gapPx;
      if (!_plan!.legacy) px += _namedHeaderPx;
      if (heatingLowBatteries(zone.thermostats, _values).isNotEmpty) px += _batteryPx;
      final status = _warmupStatus(zone, now) != null;
      if (_override(zone, now) != null || status) px += _manualPx;
      if (_override(zone, now) != null && status) px += _manualPx;
      if (_warmupNextLine(zone, now) != null) px += _warmupLinePx;
      if (_warmupLearning(zone) != null) px += _warmupLinePx;
      if (_weekExpanded(zone)) px += 7 * _dayRowPx;
    }
    if (_stationLine() != null) px += _warmupLinePx;
    return (px / heightUnit).ceilToDouble();
  }

  @override
  Widget buildInternal(BuildContext context, bool parentFlexible) {
    _dashboard = context.findAncestorStateOfType<DashboardState>();
    _ensureValuesTimer();
    final w = _HeatingBody(module: this);
    return parentFlexible ? Expanded(child: w) : w;
  }

  /// Runs while a dashboard shows the widget and stops by itself when that is gone.
  void _ensureValuesTimer() {
    if (_valuesTimer != null || _dashboard == null) return;
    _valuesTimer = Timer.periodic(heatingValuesInterval, (_) async {
      final dashboard = _dashboard;
      if (dashboard == null || !dashboard.mounted) {
        _valuesTimer?.cancel();
        _valuesTimer = null;
        return;
      }
      await _loadValues(reuseCommands: true);
      await _loadWarmup();
      dashboard.redraw();
    });
  }

  @override
  Future<void> refreshInternal() async {
    _raw = null;
    _plan = null;
    _zones = null;
    _thermostats = const [];
    try {
      final instance = await SmartServiceService.getInstance(instance_id);
      _instance = instance;
      final params = instance.parameters ?? const <SmartServiceParameter>[];
      final schedule = params.where((p) => p.id == "schedule").firstOrNull?.value;
      final setback = params.where((p) => p.id == "setback").firstOrNull?.value;
      try {
        _plan = HeatingPlan.parse(schedule is String ? schedule : "", setback);
        _thermostats = parseHeatingThermostats(params.where((p) => p.id == "thermostats").firstOrNull?.value);
        _zones = _plan!.resolve(_thermostats);
        _error = null;
      } on HeatingScheduleException catch (e) {
        _raw = schedule?.toString();
        _error = "The stored plan cannot be used: $e";
      }
    } catch (e, s) {
      ErrorReporter.log("Could not load the heating plan", e, s);
      _error = _describe(e, "load the heating plan");
    }
    if (_zones != null) {
      await _loadValues(reuseCommands: false);
    } else {
      _values = const {};
      _commands = null;
    }
    await _loadWarmup();
  }

  /// Reads the newest export row of every zone in one request. An export without a table yet
  /// means no rows so far; any other failure is logged and leaves the widget without warm-up information.
  Future<void> _loadWarmup() async {
    final warmup = _warmup, zones = _zones;
    if (warmup == null || zones == null) {
      _warmupRows = null;
      return;
    }
    try {
      final keys = [for (final z in zones) z.key];
      final results = await DbQueryService.queryAll([
        for (final key in keys)
          DbQuery(warmup.exportId, null, null, null, null, 1, null, null,
              [for (final c in heatingWarmupColumns) QueriesRequestElementColumn(c, null, null, null, null, null)],
              [QueriesRequestElementFilter("zone", "=", null, key)]),
      ]);
      _warmupRows = heatingWarmupRows(keys, results, (m) => ErrorReporter.log(m));
    } on DioException catch (e, s) {
      if (exportHasNoTable(e.response?.statusCode, e.response?.data)) {
        _warmupRows = const {};
      } else {
        ErrorReporter.log("Could not read the warm-up export", e, s);
        _warmupRows = null;
      }
    } catch (e, s) {
      ErrorReporter.log("Could not read the warm-up export", e, s);
      _warmupRows = null;
    }
  }

  /// Reads room temperature, set point and battery of every thermostat in one batch. Any failure
  /// is logged and leaves the widget without these values, as before they existed.
  Future<void> _loadValues({required bool reuseCommands}) async {
    try {
      if (!reuseCommands || _commands == null) await _buildCommands();
      final commands = _commands!;
      if (commands.isEmpty) {
        _values = const {};
        return;
      }
      final answers = await DeviceCommandsService.runCommands(commands, true);
      _values = heatingValuesFromAnswers(_asked, answers);
    } catch (e, s) {
      ErrorReporter.log("Could not read the thermostat values", e, s);
      _values = const {};
      _commands = null;
    }
  }

  Future<void> _buildCommands() async {
    final ids = [for (final t in _thermostats) t.id];
    final devices = ids.isEmpty ? <DeviceInstance>[] : await DevicesService.getDevicesByIds(ids);
    final typeIds = {for (final d in devices) d.device_type_id}.toList();
    final types = typeIds.isEmpty ? [] : await DeviceTypesService.getDeviceTypes(typeIds);
    final commands = <DeviceCommand>[];
    final asked = <(String, HeatingValueKind)>[];
    for (final device in devices) {
      final type = types.where((t) => t.id == device.device_type_id).firstOrNull;
      if (type == null) continue;
      for (final kind in HeatingValueKind.values) {
        final source = findHeatingValueSource(type, kind);
        if (source == null) continue;
        commands.add(source.toCommand(device));
        asked.add((device.id, kind));
      }
    }
    _asked = asked;
    _commands = commands;
  }

  /// A 403 is named as such; a 404 means the instance is gone while the
  /// dashboard still holds the widget.
  String _describe(Object e, String action) {
    if (e is UnexpectedStatusCodeException && e.code == 403) return "Not allowed to $action (403 Forbidden).";
    if (e is UnexpectedStatusCodeException && e.code == 404 && action == "load the heating plan") {
      return "This smart service was deleted. Remove this widget.";
    }
    return "Could not $action: $e";
  }

  Future<void> _edit(BuildContext context) async {
    final current = _plan;
    if (current == null) return;
    final dashboard = context.findAncestorStateOfType<DashboardState>();
    final plan = await Navigator.push<HeatingPlan>(
        context, MaterialPageRoute(builder: (_) => HeatingZonesEditPage(initial: current, thermostats: _thermostats)));
    final instance = _instance;
    if (plan == null || instance == null) return;
    try {
      await saveHeatingPlan(instance, plan);
    } catch (e, s) {
      ErrorReporter.log("Could not save the heating plan", e, s);
      Toast.showToastNoContext(_describe(e, "save the heating plan"));
    }
    await refresh();
    dashboard?.redraw();
  }
}

class _HeatingBody extends StatefulWidget {
  const _HeatingBody({required this.module});

  final SmSeHeatingSchedule module;

  @override
  State<_HeatingBody> createState() => _HeatingBodyState();
}

class _HeatingBodyState extends State<_HeatingBody> {
  SmSeHeatingSchedule get m => widget.module;

  /// The height follows the toggle, so the dashboard has to lay out again.
  void _toggleWeek(HeatingZone zone) {
    final dashboard = context.findAncestorStateOfType<DashboardState>();
    setState(() => m._weekOpen[zone.name] = !m._weekExpanded(zone));
    dashboard?.redraw();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final zones = m._zones;
    final plan = m._plan;
    if (zones == null || plan == null) {
      return Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m._error ?? "No heating plan loaded."),
            if (m._raw != null) Text(m._raw!, style: theme.textTheme.bodySmall),
            if (plan != null) _editButton(context),
          ]),
        ),
      );
    }

    final now = DateTime.now().toUtc();
    return Padding(
      padding: const EdgeInsets.all(Spacing.md),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(child: Text(m._instance?.name ?? "Heating", style: theme.textTheme.titleSmall)),
              if (m._instance != null) _statusPill(context, m._instance!),
            ]),
            const SizedBox(height: Spacing.xxs),
            for (final zone in zones) _zoneBlock(context, zone, now, named: !plan.legacy),
            if (m._stationLine() != null)
              SizedBox(
                height: SmSeHeatingSchedule._warmupLinePx,
                child: Text(m._stationLine()!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [_legend(context), _editButton(context)],
            ),
          ],
        ),
      ),
    );
  }

  Widget _editButton(BuildContext context) => Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          icon: const Icon(Icons.edit),
          label: const Text("Edit plan"),
          onPressed: () => m._edit(context),
        ),
      );

  /// A pill in a colour of the theme; [tooltip] carries the full text of a shortened one.
  Widget _pill(BuildContext context, String text, Color color, {String? tooltip, IconData? icon}) {
    final theme = Theme.of(context);
    Widget pill = Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: Spacing.xxs),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: Spacing.xxs)],
        Flexible(
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelMedium?.copyWith(color: color)),
        ),
      ]),
    );
    if (tooltip != null) pill = Tooltip(message: tooltip, triggerMode: TooltipTriggerMode.tap, child: pill);
    return pill;
  }

  Color _success(BuildContext context) =>
      Theme.of(context).extension<AppColors>()?.success ?? Theme.of(context).colorScheme.primary;

  Color _warn(BuildContext context) =>
      Theme.of(context).extension<AppColors>()?.warn ?? Theme.of(context).colorScheme.tertiary;

  Widget _statusPill(BuildContext context, SmartServiceInstance instance) {
    final scheme = Theme.of(context).colorScheme;
    final error = instance.error;
    if (error != null && error.isNotEmpty) {
      return _pill(context, error, Theme.of(context).extension<AppColors>()?.error ?? scheme.error, tooltip: error);
    }
    if (!instance.ready) return _pill(context, "Starting", scheme.onSurfaceVariant);
    return _pill(context, "Running", _success(context));
  }

  Widget _legend(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(formatHeatingTemperature(heatingColdTemperature), style: style),
      const SizedBox(width: Spacing.xxs),
      Container(
        width: 40,
        height: 8,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          gradient: const LinearGradient(colors: [heatingColdColor, heatingWarmColor]),
        ),
      ),
      const SizedBox(width: Spacing.xxs),
      Text(formatHeatingTemperature(heatingWarmTemperature), style: style),
    ]);
  }

  /// A legacy plan has one unnamed zone and shows no zone header.
  Widget _zoneBlock(BuildContext context, HeatingZone zone, DateTime now, {required bool named}) {
    final theme = Theme.of(context);
    final next = zone.schedule.nextSwitch(now);
    final planned = zone.schedule.target(now);
    final room = heatingMeanRoom([for (final t in zone.thermostats) m._values[t.id]?.room]);
    final low = heatingLowBatteries(zone.thermostats, m._values);
    final manual = m._override(zone, now);
    final expanded = m._weekExpanded(zone);
    final warmupStatus = m._warmupStatus(zone, now);
    final warmupNext = m._warmupNextLine(zone, now);
    final warmupLearning = m._warmupLearning(zone);
    final hatches = m._warmup == null ? null : m._warmupRow(zone)?.windows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (named) ...[
          Text(zone.name, style: theme.textTheme.titleSmall),
          Text(zone.thermostats.map((t) => t.label).join(", "),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
        ],
        if (low.isNotEmpty)
          Wrap(spacing: Spacing.sm, children: [
            for (final (t, level) in low)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.battery_alert, size: 16, color: _warn(context)),
                const SizedBox(width: Spacing.xxs),
                Text("${t.label} ${level.round()} %", style: theme.textTheme.bodySmall?.copyWith(color: _warn(context))),
              ]),
          ]),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(formatHeatingTemperature(room ?? planned), style: theme.textTheme.headlineMedium),
          if (room != null) ...[
            const SizedBox(width: Spacing.sm),
            Text("target ${formatHeatingTemperature(planned)}", style: theme.textTheme.bodyMedium),
          ],
        ]),
        SizedBox(
          height: 20,
          child: next == null ? null : Text(_nextLine(now, next), style: theme.textTheme.bodyMedium),
        ),
        if (warmupNext != null) Text(warmupNext, style: theme.textTheme.bodyMedium),
        if (warmupLearning != null) Text(warmupLearning, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        if (manual != null || warmupStatus != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(spacing: Spacing.sm, runSpacing: Spacing.xxs, children: [
              if (warmupStatus != null)
                _pill(context, warmupStatus, theme.colorScheme.primary, icon: Icons.trending_up, tooltip: warmupStatus),
              if (manual != null) _pill(context, _manualText(now, manual), _warn(context), icon: Icons.pan_tool_alt),
            ]),
          ),
        // Room for the line about the heat-up time (SNRGY-3607).
        const SizedBox(height: Spacing.sm),
        _TimeOverview(
          plan: zone.schedule,
          now: now,
          expanded: expanded,
          warmupWindows: hatches ?? const [],
          lightHatch: m._warmup?.mode == HeatingWarmupMode.show,
        ),
        _weekToggle(context, zone, expanded),
        const SizedBox(height: Spacing.sm),
      ],
    );
  }

  Widget _weekToggle(BuildContext context, HeatingZone zone, bool expanded) => Semantics(
        button: true,
        label: expanded ? "Hide week" : "Show week",
        excludeSemantics: true,
        child: InkWell(
          onTap: () => _toggleWeek(zone),
          child: SizedBox(
            height: 32,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text("Week", style: Theme.of(context).textTheme.labelMedium),
              Icon(expanded ? Icons.expand_less : Icons.expand_more),
            ]),
          ),
        ),
      );

  /// "17 °C from 20:00, in 3 h 10 min", with the weekday when the switch is not today.
  static String _nextLine(DateTime now, HeatingSwitch next) {
    final countdown = heatingCountdown(next.at.difference(now));
    return "${formatHeatingTemperature(next.temperature)} from ${heatingClockText(now, next.at)}${countdown == null ? "" : ", $countdown"}";
  }

  static String _manualText(DateTime now, HeatingOverride o) {
    final temperature = o.temperature == null ? "" : " ${formatHeatingTemperature(o.temperature!)}";
    final until = o.until == null ? "" : " until ${heatingClockText(now, o.until!)}";
    return "Manual$temperature$until";
  }
}

/// The row of today and, below it when [expanded], the seven days of the week.
class _TimeOverview extends StatelessWidget {
  const _TimeOverview({
    required this.plan,
    required this.now,
    required this.expanded,
    this.warmupWindows = const [],
    this.lightHatch = false,
  });

  final HeatingSchedule plan;
  final DateTime now;
  final bool expanded;

  /// The warm-up phases to hatch, and whether they are only a hint (mode show) rather than the plan.
  final List<HeatingWarmupWindow> warmupWindows;
  final bool lightHatch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final local = heatingLocalTime(now);
    final today = local.weekday - 1;
    final nowMinute = local.hour * 60 + local.minute;
    final base = theme.colorScheme.surfaceContainerHighest;
    Widget dayRow(String label, int d, {required bool labels, bool strong = false}) => SizedBox(
          height: 22,
          child: Row(children: [
            SizedBox(
              width: _labelWidth,
              child: Text(label,
                  style: theme.textTheme.labelMedium?.copyWith(fontWeight: strong ? FontWeight.bold : FontWeight.normal)),
            ),
            Expanded(
              child: CustomPaint(
                size: const Size.fromHeight(20),
                painter: _DayBarPainter(
                  segments: plan.segmentsOf(d),
                  hatches: heatingWarmupHatches(warmupWindows, now, d),
                  hatchAlpha: lightHatch ? 0.45 : 1,
                  base: base,
                  nowMinute: d == today ? nowMinute : null,
                  nowColor: theme.colorScheme.onSurface,
                  labelColor: theme.colorScheme.onSurfaceVariant,
                  barHeight: labels ? 20 : 14,
                  showLabels: labels,
                ),
              ),
            ),
          ]),
        );
    return Column(children: [
      Row(children: [
        const SizedBox(width: _labelWidth),
        Expanded(
          child: SizedBox(
            height: 16,
            child: Stack(children: [
              for (final h in const [0, 6, 12, 18, 24])
                Align(alignment: Alignment(-1 + 2 * h / 24, 0), child: Text("$h", style: theme.textTheme.labelSmall)),
            ]),
          ),
        ),
      ]),
      dayRow("Today", today, labels: true, strong: true),
      if (expanded)
        for (var d = 0; d < 7; d++) dayRow(heatingDayNames[d], d, labels: false, strong: d == today),
    ]);
  }

  static const _labelWidth = 44.0;
}

class _DayBarPainter extends CustomPainter {
  _DayBarPainter({
    required this.segments,
    this.hatches = const [],
    this.hatchAlpha = 1,
    required this.base,
    required this.nowMinute,
    required this.nowColor,
    required this.labelColor,
    required this.barHeight,
    required this.showLabels,
  });

  final List<HeatingSegment> segments;
  final List<HeatingHatch> hatches;
  final double hatchAlpha;
  final Color base;
  final int? nowMinute;
  final Color nowColor, labelColor;
  final double barHeight;
  final bool showLabels;

  /// Dark enough to read on both ends of the colour scale.
  static const _onHeat = Color(0xDD000000);

  @override
  void paint(Canvas canvas, Size size) {
    final y = (size.height - barHeight) / 2;
    final scale = size.width / heatingMinutesPerDay;
    for (final s in segments) {
      final rect = Rect.fromLTRB(s.from * scale, y, s.to * scale, y + barHeight);
      canvas.drawRect(rect, Paint()..color = s.planned ? heatingTemperatureColor(s.temperature) : base);
      if (!showLabels) continue;
      final t = s.temperature;
      final tp = TextPainter(
        text: TextSpan(
          text: t == t.roundToDouble() ? "${t.toInt()}°" : "$t°",
          style: TextStyle(fontSize: 11, color: s.planned ? _onHeat : labelColor),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // Drawn only where it fits, so narrow segments stay unlabelled.
      if (tp.width + 4 <= rect.width) tp.paint(canvas, Offset(rect.left + (rect.width - tp.width) / 2, y + (barHeight - tp.height) / 2));
    }
    for (final h in hatches) {
      _hatch(canvas, Rect.fromLTRB(h.from * scale, y, h.to * scale, y + barHeight), heatingTemperatureColor(h.temperature));
    }
    final now = nowMinute;
    if (now != null) {
      canvas.drawRect(Rect.fromLTWH(now * scale - 1, y - 2, 2, barHeight + 4), Paint()..color = nowColor);
    }
  }

  /// Diagonal stripes in [color] over a faint fill, clipped to [rect].
  void _hatch(Canvas canvas, Rect rect, Color color) {
    canvas.save();
    canvas.clipRect(rect);
    canvas.drawRect(rect, Paint()..color = color.withValues(alpha: 0.25 * hatchAlpha));
    final stripe = Paint()
      ..color = color.withValues(alpha: hatchAlpha)
      ..strokeWidth = 1.5;
    const step = 5.0;
    for (var x = rect.left - rect.height; x < rect.right; x += step) {
      canvas.drawLine(Offset(x, rect.bottom), Offset(x + rect.height, rect.top), stripe);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DayBarPainter old) =>
      old.segments != segments ||
      old.hatches != hatches ||
      old.hatchAlpha != hatchAlpha ||
      old.base != base ||
      old.nowMinute != nowMinute ||
      old.nowColor != nowColor ||
      old.labelColor != labelColor ||
      old.barHeight != barHeight ||
      old.showLabels != showLabels;
}
