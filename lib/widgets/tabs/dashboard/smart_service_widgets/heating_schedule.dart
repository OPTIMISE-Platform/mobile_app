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

// Dashboard widget of the Heizungssteuerung: current target, next switch point and the week.

import 'package:flutter/material.dart';
import 'package:mobile_app/exceptions/unexpected_status_code_exception.dart';
import 'package:mobile_app/models/smart_service.dart';
import 'package:mobile_app/services/smart_service.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/toast.dart';
import 'package:mobile_app/widgets/tabs/dashboard/dashboard.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/base.dart';
import 'package:mobile_app/widgets/tabs/smart-services/heating_schedule_editor.dart';
import 'package:mobile_app/widgets/tabs/smart-services/heating_schedule_model.dart';
import 'package:mobile_app/widgets/tabs/smart-services/instance_parameters.dart';

class SmSeHeatingSchedule extends SmartServiceModuleWidget {
  static const _fullUnits = 13.0;
  static const _messageUnits = 3.0;

  SmartServiceInstance? _instance;
  HeatingSchedule? _schedule;
  String? _error;

  /// The stored schedule text when it cannot be read, so the user sees what is there.
  String? _raw;

  @override
  setPreview(bool enabled) => null;

  @override
  double width = 1;

  @override
  Future<void> configure(dynamic data) async {}

  @override
  double get height => _schedule == null ? _messageUnits : _fullUnits;

  @override
  Widget buildInternal(BuildContext context, bool parentFlexible) {
    final w = _HeatingBody(module: this);
    return parentFlexible ? Expanded(child: w) : w;
  }

  @override
  Future<void> refreshInternal() async {
    _raw = null;
    try {
      final instance = await SmartServiceService.getInstance(instance_id);
      _instance = instance;
      final params = instance.parameters ?? const <SmartServiceParameter>[];
      final schedule = params.where((p) => p.id == "schedule").firstOrNull?.value;
      final setback = params.where((p) => p.id == "setback").firstOrNull?.value;
      try {
        _schedule = HeatingSchedule.parse(schedule is String ? schedule : "", setback);
        _error = null;
      } on HeatingScheduleException catch (e) {
        _schedule = null;
        _raw = schedule?.toString();
        _error = "The stored plan cannot be read: $e";
      }
    } catch (e, s) {
      ErrorReporter.log("Could not load the heating plan", e, s);
      _schedule = null;
      _error = _describe(e, "load the heating plan");
    }
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
    final schedule = _schedule ?? const HeatingSchedule(HeatingSchedule.defaultWindows, 17);
    final dashboard = context.findAncestorStateOfType<DashboardState>();
    final plan = await Navigator.push<HeatingSchedule>(
        context, MaterialPageRoute(builder: (_) => HeatingScheduleEditPage(initial: schedule)));
    final instance = _instance;
    if (plan == null || instance == null) return;
    try {
      await saveHeatingSchedule(instance, plan);
    } catch (e, s) {
      ErrorReporter.log("Could not save the heating plan", e, s);
      Toast.showToastNoContext(_describe(e, "save the heating plan"));
    }
    await refresh();
    dashboard?.redraw();
  }
}

class _HeatingBody extends StatelessWidget {
  const _HeatingBody({required this.module});

  final SmSeHeatingSchedule module;

  @override
  Widget build(BuildContext context) {
    final m = module;
    final theme = Theme.of(context);
    final plan = m._schedule;
    if (plan == null) {
      return Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m._error ?? "No heating plan loaded."),
            if (m._raw != null) Text(m._raw!, style: theme.textTheme.bodySmall),
          ]),
        ),
      );
    }

    final now = DateTime.now().toUtc();
    final next = plan.nextSwitch(now);
    return Padding(
      padding: const EdgeInsets.all(Spacing.md),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(m._instance?.name ?? "Heating", style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.xxs),
            Text(formatHeatingTemperature(plan.target(now)), style: theme.textTheme.headlineMedium),
            SizedBox(
              height: 20,
              child: next == null ? null : Text(_nextLine(now, next), style: theme.textTheme.bodyMedium),
            ),
            // Room for the line about the heat-up time (SNRGY-3607).
            const SizedBox(height: Spacing.sm),
            _WeekOverview(plan: plan, now: now),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.edit),
                label: const Text("Edit plan"),
                onPressed: () => m._edit(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "17 °C from 20:00", with the weekday when the switch is not today.
  static String _nextLine(DateTime now, HeatingSwitch next) {
    final local = heatingLocalTime(next.at);
    final today = heatingLocalTime(now);
    final sameDay = local.year == today.year && local.month == today.month && local.day == today.day;
    final time = formatHeatingMinutes(local.hour * 60 + local.minute);
    return "${formatHeatingTemperature(next.temperature)} from ${sameDay ? "" : "${heatingDayNames[local.weekday - 1]} "}$time";
  }
}

class _WeekOverview extends StatelessWidget {
  const _WeekOverview({required this.plan, required this.now});

  final HeatingSchedule plan;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final local = heatingLocalTime(now);
    final nowMinute = local.hour * 60 + local.minute;
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
      for (var d = 0; d < 7; d++)
        SizedBox(
          height: 22,
          child: Row(children: [
            SizedBox(width: _labelWidth, child: Text(heatingDayNames[d], style: theme.textTheme.labelMedium)),
            Expanded(
              child: CustomPaint(
                size: const Size.fromHeight(14),
                painter: _DayBarPainter(
                  segments: plan.segmentsOf(d),
                  base: theme.colorScheme.surfaceContainerHighest,
                  nowMinute: d == local.weekday - 1 ? nowMinute : null,
                  nowColor: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ]),
        ),
    ]);
  }

  static const _labelWidth = 36.0;
}

class _DayBarPainter extends CustomPainter {
  _DayBarPainter({required this.segments, required this.base, required this.nowMinute, required this.nowColor});

  final List<HeatingSegment> segments;
  final Color base;
  final int? nowMinute;
  final Color nowColor;

  /// Blue at the cold end of the editor's range, orange at the warm end.
  static Color _heat(double t) {
    final f = ((t - heatingMinTemperature) / (heatingMaxTemperature - heatingMinTemperature)).clamp(0.0, 1.0);
    return Color.lerp(const Color(0xFF64B5F6), const Color(0xFFFF8A3D), f)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final y = (size.height - 14) / 2;
    final scale = size.width / heatingMinutesPerDay;
    for (final s in segments) {
      final paint = Paint()..color = s.planned ? _heat(s.temperature) : base;
      canvas.drawRect(Rect.fromLTRB(s.from * scale, y, s.to * scale, y + 14), paint);
    }
    final now = nowMinute;
    if (now != null) {
      canvas.drawRect(Rect.fromLTWH(now * scale - 1, y - 2, 2, 18), Paint()..color = nowColor);
    }
  }

  @override
  bool shouldRepaint(_DayBarPainter old) =>
      old.segments != segments || old.base != base || old.nowMinute != nowMinute || old.nowColor != nowColor;
}
