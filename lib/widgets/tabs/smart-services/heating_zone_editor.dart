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


// Editor of the zones of the Heizungssteuerung plan, used by the dashboard widget (as a full-screen
// page) and by the instance edit screen in place of the text field of the schedule parameter.

import 'package:flutter/material.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/tabs/smart-services/heating_schedule_editor.dart';
import 'package:mobile_app/widgets/tabs/smart-services/heating_schedule_model.dart';

/// What the editor holds for one zone while the user edits it.
class _ZoneRow {
  final key = UniqueKey();
  final TextEditingController name;
  final List<dynamic> devices;
  bool rest, ownSetback, windowsValid = true;
  List<HeatingWindow> windows;
  double setback;

  _ZoneRow(this.name, this.devices, this.rest, this.windows, this.ownSetback, this.setback);

  factory _ZoneRow.of(HeatingZoneDef z, double planSetback) => _ZoneRow(
      TextEditingController(text: z.name), [...?z.devices], z.devices == null, z.windows, z.setback != null, z.setback ?? planSetback);

  String effectiveName(int i) => name.text.trim().isEmpty ? "Zone ${i + 1}" : name.text.trim();
}

/// Edits the zones of [initial] over the selected [thermostats] and, when [showSetback], the setback
/// that zones without their own use. [onChanged] gets the plan after each change, null while it is
/// invalid. The editor takes part in the validation of an enclosing Form.
class HeatingZoneEditor extends StatefulWidget {
  final HeatingPlan initial;
  final List<HeatingThermostat> thermostats;
  final bool showSetback;
  final ValueChanged<HeatingPlan?> onChanged;

  const HeatingZoneEditor(
      {super.key, required this.initial, required this.thermostats, required this.onChanged, this.showSetback = true});

  @override
  State<HeatingZoneEditor> createState() => _HeatingZoneEditorState();
}

class _HeatingZoneEditorState extends State<HeatingZoneEditor> {
  late final List<_ZoneRow> _rows = [for (final z in widget.initial.zones) _ZoneRow.of(z, widget.initial.setback)];
  final List<_ZoneRow> _removed = [];
  late double _setback = widget.initial.setback;
  String? _problem;

  @override
  void initState() {
    super.initState();
    if (_rows.isEmpty) _rows.add(_newRow(0));
    _problem = _check();
  }

  @override
  void didUpdateWidget(HeatingZoneEditor old) {
    super.didUpdateWidget(old);
    if (widget.initial.setback != old.initial.setback) _setback = widget.initial.setback;
    if (_ids(old.thermostats) == _ids(widget.thermostats)) return;
    _problem = _check();
    // The parent may be rebuilding right now, so it hears of the new validity after the frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onChanged(_plan());
    });
  }

  @override
  void dispose() {
    for (final r in [..._rows, ..._removed]) {
      r.name.dispose();
    }
    super.dispose();
  }

  static String _ids(List<HeatingThermostat> t) => t.map((e) => e.id).join("\n");

  /// An empty zone without thermostats, named "Zone N" with the first N not taken, and the default window.
  _ZoneRow _newRow(int count) {
    var n = count + 1;
    while (_rows.any((r) => r.name.text.trim() == "Zone $n")) {
      n++;
    }
    return _ZoneRow(TextEditingController(text: "Zone $n"), [], false, HeatingSchedule.defaultWindows, false, _setback);
  }

  HeatingPlan _plan() => HeatingPlan([
        for (final (i, r) in _rows.indexed)
          HeatingZoneDef(_rows.length == 1 ? r.name.text.trim() : r.effectiveName(i), r.rest ? null : [...r.devices], r.windows, r.ownSetback ? r.setback : null)
      ], _setback);

  String? _check() {
    if (_rows.any((r) => !r.windowsValid)) return "Fix the time windows.";
    return _plan().problem(widget.thermostats);
  }

  void _changed(VoidCallback change) {
    setState(change);
    _problem = _check();
    widget.onChanged(_problem == null ? _plan() : null);
  }

  /// The name of the zone that holds [id], when it is not [except].
  String? _holder(String id, _ZoneRow except) {
    for (final (i, r) in _rows.indexed) {
      if (r != except && !r.rest && r.devices.contains(id)) return r.effectiveName(i);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final windowsProblem = _rows.any((r) => !r.windowsValid);
    return FormField<bool>(
      validator: (_) => _problem,
      builder: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showSetback) ...[
            Text("Setback temperature", style: theme.textTheme.titleSmall),
            const Text("Applies outside every time window, in zones without their own."),
            heatingStepper(
              formatHeatingTemperature(_setback),
              onMinus: _setback > heatingMinTemperature ? () => _changed(() => _setback = heatingMove(_setback, -1, 1)) : null,
              onPlus: _setback < heatingMaxTemperature ? () => _changed(() => _setback = heatingMove(_setback, 1, 1)) : null,
            ),
            const SizedBox(height: Spacing.sm),
          ],
          for (final (i, r) in _rows.indexed) _zoneCard(context, i, r),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text("Add zone"),
              onPressed: () => _changed(() => _rows.add(_newRow(_rows.length))),
            ),
          ),
          // Window problems are already shown at their window.
          if (_problem != null && !windowsProblem) Text(_problem!, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ),
    );
  }

  Widget _zoneCard(BuildContext context, int i, _ZoneRow r) {
    final theme = Theme.of(context);
    final restElsewhere = _rows.any((o) => o != r && o.rest);
    return Card(
      key: r.key,
      elevation: 0,
      color: theme.colorScheme.surfaceContainer,
      margin: const EdgeInsets.only(bottom: Spacing.md),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: r.name,
                  decoration: InputDecoration(labelText: "Zone name", hintText: "Zone ${i + 1}"),
                  onChanged: (_) => _changed(() {}),
                ),
              ),
              IconButton(
                tooltip: "Delete zone",
                icon: const Icon(Icons.delete),
                onPressed: _rows.length > 1
                    ? () => _changed(() {
                          _rows.remove(r);
                          _removed.add(r);
                        })
                    : null,
              ),
            ]),
            Row(children: [
              const Expanded(child: Text("All other thermostats")),
              Switch.adaptive(
                value: r.rest,
                onChanged: r.rest || !restElsewhere ? (on) => _changed(() => r.rest = on) : null,
              ),
            ]),
            if (!r.rest)
              for (final t in widget.thermostats) _deviceTile(r, t),
            // Keyed by the row, so the plan editor keeps its windows when zones come and go.
            HeatingScheduleEditor(
              key: ValueKey(r.key),
              initial: HeatingSchedule(r.windows, 0),
              showSetback: false,
              onChanged: (s) => _changed(() {
                r.windowsValid = s != null;
                if (s != null) r.windows = s.windows;
              }),
            ),
            Row(children: [
              const Expanded(child: Text("Own setback temperature")),
              Switch.adaptive(
                value: r.ownSetback,
                onChanged: (on) => _changed(() {
                  r.ownSetback = on;
                  // Starts at the global setback, snapped into the editor's range.
                  if (on) r.setback = heatingMove(_setback, 0, 1);
                }),
              ),
            ]),
            if (r.ownSetback)
              heatingStepper(
                formatHeatingTemperature(r.setback),
                onMinus: r.setback > heatingMinTemperature ? () => _changed(() => r.setback = heatingMove(r.setback, -1, 1)) : null,
                onPlus: r.setback < heatingMaxTemperature ? () => _changed(() => r.setback = heatingMove(r.setback, 1, 1)) : null,
              ),
          ],
        ),
      ),
    );
  }

  Widget _deviceTile(_ZoneRow r, HeatingThermostat t) {
    final holder = _holder(t.id, r);
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      title: Text(t.label),
      subtitle: holder == null ? null : Text("In $holder"),
      value: r.devices.contains(t.id),
      onChanged: holder != null && !r.devices.contains(t.id) ? null : (on) => _changed(() => on == true ? r.devices.add(t.id) : r.devices.remove(t.id)),
    );
  }
}

/// The full-screen editor of the widget. Pops with the new plan after the user confirmed the
/// restart note, or with null when cancelled.
class HeatingZonesEditPage extends StatefulWidget {
  final HeatingPlan initial;
  final List<HeatingThermostat> thermostats;

  const HeatingZonesEditPage({super.key, required this.initial, required this.thermostats});

  @override
  State<HeatingZonesEditPage> createState() => _HeatingZonesEditPageState();
}

class _HeatingZonesEditPageState extends State<HeatingZonesEditPage> {
  // A stored plan that is already invalid cannot be saved as it is.
  late HeatingPlan? _current = widget.initial.problem(widget.thermostats) == null ? widget.initial : null;

  Future<void> _save() async {
    final plan = _current;
    if (plan == null) return;
    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog.adaptive(
        title: const Text("Save the heating plan?"),
        content: const Text(heatingRestartNote),
        actions: [
          TextButton(child: const Text("Cancel"), onPressed: () => Navigator.pop(dialogContext, false)),
          TextButton(child: const Text("Save"), onPressed: () => Navigator.pop(dialogContext, true)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.pop(context, plan);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Heating plan"),
        actions: [TextButton(onPressed: _current == null ? null : _save, child: const Text("Save"))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          HeatingZoneEditor(
              initial: widget.initial, thermostats: widget.thermostats, onChanged: (p) => setState(() => _current = p))
        ],
      ),
    );
  }
}
