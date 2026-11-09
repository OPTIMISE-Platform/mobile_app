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

// Editor of the weekly plan of one Heizungssteuerung zone; heating_zone_editor.dart builds the zone editor on it.

import 'package:flutter/material.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/tabs/smart-services/heating_schedule_model.dart';

const heatingDayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

const heatingMinTemperature = 5.0;
const heatingMaxTemperature = 30.0;
const _step = 0.5;

const heatingRestartNote = "Saving restarts the heating control and sets the temperature of the plan right away.";

/// One [step] up or down from the nearest multiple of [step], kept in 5..30.
/// Stored values off the grid or out of range change only through this.
double heatingMove(double value, int direction, double step) =>
    ((value / step).round() * step + direction * step).clamp(heatingMinTemperature, heatingMaxTemperature);

String formatHeatingTemperature(double t) => t == t.roundToDouble() ? "${t.toInt()} °C" : "$t °C";

/// What the editor holds for one window while the user edits it.
class _Row {
  final Set<int> days;
  int from, to;
  double temperature;
  bool allDay;

  _Row(this.days, this.from, this.to, this.temperature, this.allDay);

  factory _Row.of(HeatingWindow w) => _Row({...w.weekdays}, w.from, w.to, w.temperature, w.allDay);

  /// A whole-day row keeps its [from], so a stored 24:00 to 24:00 stays as it is.
  HeatingWindow get window => HeatingWindow(days.toList()..sort(), from, allDay ? from : to, temperature);

  String? get problem {
    if (days.isEmpty) return "Pick at least one weekday.";
    if (!allDay && from == to) return "From and To must differ, or choose All day.";
    if (!temperature.isFinite) return "The temperature must be a number.";
    if (from < 0 || from > heatingMinutesPerDay || to < 0 || to > heatingMinutesPerDay) return "The times must be valid.";
    return null;
  }
}

/// Edits the windows and, when [showSetback], the setback. [onChanged] gets
/// the plan after each change, null while it is invalid. The editor takes part
/// in the validation of an enclosing Form.
class HeatingScheduleEditor extends StatefulWidget {
  final HeatingSchedule initial;
  final bool showSetback;
  final ValueChanged<HeatingSchedule?> onChanged;

  const HeatingScheduleEditor({super.key, required this.initial, required this.onChanged, this.showSetback = true});

  @override
  State<HeatingScheduleEditor> createState() => _HeatingScheduleEditorState();
}

class _HeatingScheduleEditorState extends State<HeatingScheduleEditor> {
  late final List<_Row> _rows = [for (final w in widget.initial.windows) _Row.of(w)];
  late double _setback = widget.initial.setback;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _problem = _check();
  }

  String? _check() {
    for (final r in _rows) {
      final p = r.problem;
      if (p != null) return p;
    }
    return null;
  }

  void _changed(VoidCallback change) {
    setState(change);
    _problem = _check();
    widget.onChanged(_problem == null ? HeatingSchedule([for (final r in _rows) r.window], _setback) : null);
  }

  Future<void> _pick(_Row row, bool from) async {
    final current = from ? row.from : row.to;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (current ~/ 60) % 24, minute: current % 60),
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (picked == null || !mounted) return;
    _changed(() {
      final m = picked.hour * 60 + picked.minute;
      if (from) {
        row.from = m;
      } else {
        row.to = m;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FormField<bool>(
      validator: (_) => _problem,
      builder: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, row) in _rows.indexed) _rowCard(context, i, row),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text("Add time window"),
              onPressed: () => _changed(() => _rows.add(_Row({0, 1, 2, 3, 4}, 360, 480, 20, false))),
            ),
          ),
          if (widget.showSetback) ...[
            const SizedBox(height: Spacing.md),
            Text("Setback temperature", style: theme.textTheme.titleSmall),
            const Text("Applies outside every time window."),
            heatingStepper(
              formatHeatingTemperature(_setback),
              onMinus: _setback > heatingMinTemperature ? () => _changed(() => _setback = heatingMove(_setback, -1, 1)) : null,
              onPlus: _setback < heatingMaxTemperature ? () => _changed(() => _setback = heatingMove(_setback, 1, 1)) : null,
            ),
          ],
        ],
      ),
    );
  }

  Widget _rowCard(BuildContext context, int i, _Row row) {
    final theme = Theme.of(context);
    final problem = row.problem;
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHigh,
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(spacing: Spacing.xs, children: [
              for (var d = 0; d < 7; d++)
                FilterChip(
                  label: Text(heatingDayNames[d]),
                  selected: row.days.contains(d),
                  onSelected: (on) => _changed(() => on ? row.days.add(d) : row.days.remove(d)),
                ),
            ]),
            const SizedBox(height: Spacing.sm),
            Row(children: [
              const Text("All day"),
              Switch.adaptive(value: row.allDay, onChanged: (on) => _changed(() => row.allDay = on)),
              const Spacer(),
              IconButton(
                tooltip: "Delete time window",
                icon: const Icon(Icons.delete),
                onPressed: () => _changed(() => _rows.removeAt(i)),
              ),
            ]),
            if (!row.allDay)
              Row(children: [
                Expanded(child: _timeField("From", row.from, () => _pick(row, true))),
                const SizedBox(width: Spacing.sm),
                Expanded(child: _timeField("To", row.to, () => _pick(row, false))),
              ]),
            heatingStepper(
              formatHeatingTemperature(row.temperature),
              onMinus: row.temperature > heatingMinTemperature ? () => _changed(() => row.temperature = heatingMove(row.temperature, -1, _step)) : null,
              onPlus: row.temperature < heatingMaxTemperature ? () => _changed(() => row.temperature = heatingMove(row.temperature, 1, _step)) : null,
            ),
            if (problem != null) Text(problem, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ),
      ),
    );
  }

  Widget _timeField(String label, int minutes, VoidCallback onTap) => OutlinedButton(
        onPressed: onTap,
        child: Text("$label ${formatHeatingMinutes(minutes)}"),
      );
}

/// A temperature value between a minus and a plus button.
Widget heatingStepper(String text, {VoidCallback? onMinus, VoidCallback? onPlus}) => Row(children: [
      IconButton(tooltip: "Decrease", icon: const Icon(Icons.remove), onPressed: onMinus),
      Text(text),
      IconButton(tooltip: "Increase", icon: const Icon(Icons.add), onPressed: onPlus),
    ]);
