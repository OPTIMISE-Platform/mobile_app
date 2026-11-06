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

import 'package:flutter/material.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/process.dart';
import 'package:mobile_app/services/process_service.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/shared/relative_time.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/app_bar.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/shared/expandable_text.dart';
import 'package:mobile_app/widgets/shared/grouped_list_tile.dart';
import 'package:mobile_app/widgets/shared/sectioned_list_view.dart';
import 'package:mobile_app/widgets/tabs/processes/process_entry.dart';

/// Read-only detail of one deployment and its newest instance. A running
/// instance's debug data is requested again on open, since the list's copy may
/// be minutes old.
class ProcessDetails extends StatefulWidget {
  const ProcessDetails(this.entry, {super.key});

  final ProcessEntry entry;

  @override
  State<ProcessDetails> createState() => _ProcessDetailsState();
}

class _ProcessDetailsState extends State<ProcessDetails> {
  late ProcessEntry _entry = widget.entry;
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (_entry.instance?.hasDebug ?? false) _loadDebug();
  }

  Future<void> _loadDebug() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final debug = await ProcessService.getDebug(_entry.instance!.id);
      if (!mounted) return;
      setState(() {
        _entry = _entry.withDebug(debug);
        _loading = false;
      });
    } catch (e, s) {
      ErrorReporter.report('Could not load process details', e, s);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  String _networkName() {
    final id = _entry.deployment.networkId;
    if (id.isEmpty) return "Cloud";
    for (final n in AppState().networks) {
      if (n.id == id) return n.name;
    }
    return "Gateway";
  }

  String _time(DateTime? t) => t == null ? "-" : "${clockOrDate(t)} (${relativeTime(t)})";

  @override
  Widget build(BuildContext context) {
    final deployment = _entry.deployment;
    final instance = _entry.instance;
    final debug = _entry.debug;
    final scheme = Theme.of(context).colorScheme;

    final details = <(String, Widget)>[
      ("State", ProcessStatusChip(_entry)),
      ("Network", Text(_networkName())),
      if (instance != null) ("Started", Text(_time(instance.startedAt))),
      if (instance != null)
        ("Last activity", Text(_time(instance.lastSeen))),
      if (instance != null && instance.endedAt != null)
        ("Ended", Text(_time(instance.endedAt))),
    ];

    return Scaffold(
      appBar: MyAppBar(deployment.name).getAppBar(context, [
        ...MyAppBar.getDefaultActions(context),
      ]),
      body: Scrollbar(
        child: SectionedListView(
          physics: const AlwaysScrollableScrollPhysics(),
          leading: [
            if (deployment.description.isNotEmpty)
              ListTile(
                title: const Text("Description"),
                subtitle: ExpandableText(deployment.description, 3),
              ),
          ],
          sections: [
            ListSection<(String, Widget)>(
              id: "details",
              title: "Details",
              items: details,
              keyOf: (row) => row.$1,
              itemBuilder: (context, row, position) => GroupedListTile(
                position: position,
                hairlineInset: GroupedListTile.insetNoLeading,
                child: ListTile(
                  title: Text(row.$1),
                  trailing: ConstrainedBox(
                      constraints: BoxConstraints(
                          maxWidth: MediaQuery.sizeOf(context).width * .55),
                      child: DefaultTextStyle.merge(
                          textAlign: TextAlign.end,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                          child: row.$2)),
                ),
              ),
            ),
            ListSection<ProcessWait>(
              id: "waits",
              title: "Waiting for",
              items: debug?.waits ?? const [],
              keyOf: (w) => "${w.elementId}/${w.kind}",
              itemBuilder: (context, wait, position) => GroupedListTile(
                position: position,
                hairlineInset: GroupedListTile.insetNoLeading,
                child: ListTile(
                  title: Text(debug!.stepName(wait.elementId)),
                  subtitle: Text(wait.isTimer
                      ? "Timer${_definition(wait)}"
                      : _kindLabel(wait.kind)),
                  trailing: wait.dueAt == null
                      ? null
                      : Text("Due ${clockOrDate(wait.dueAt!)}"),
                ),
              ),
            ),
            ListSection<ProcessActiveStep>(
              id: "active",
              title: "Active steps",
              items: debug?.active ?? const [],
              keyOf: (a) => a.elementId,
              itemBuilder: (context, step, position) => GroupedListTile(
                position: position,
                hairlineInset: GroupedListTile.insetNoLeading,
                child: ListTile(
                  title: Text(step.label),
                  subtitle: step.elementType.isEmpty
                      ? null
                      : Text(step.elementType),
                  trailing: step.since == null
                      ? null
                      : Text("since ${relativeTime(step.since!)}"),
                ),
              ),
            ),
            ListSection<(int, ProcessIncident)>(
              id: "incidents",
              title: "Incidents",
              items: [
                for (final (i, inc) in (debug?.incidents ?? const []).indexed)
                  (i, inc)
              ],
              keyOf: (row) => "${row.$1}",
              itemBuilder: (context, row, position) => GroupedListTile(
                position: position,
                hairlineInset: GroupedListTile.insetIconLeading,
                child: ListTile(
                  leading:
                      Icon(Icons.error, color: context.appColors.error),
                  title: Text(row.$2.message,
                      style: TextStyle(color: context.appColors.error)),
                  subtitle: _incidentSubtitle(row.$2),
                ),
              ),
            ),
          ],
          trailing: [
            if (_loading)
              const Padding(
                padding: Spacing.inset,
                child: Center(child: DelayedCircularProgressIndicator()),
              ),
            if (_failed)
              Padding(
                padding: Spacing.inset,
                child: Center(
                  child: TextButton(
                      onPressed: _loadDebug, child: const Text("Retry")),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Step and time of an incident, null when the engine sent neither.
  Widget? _incidentSubtitle(ProcessIncident incident) {
    final time = incident.time;
    final text = [
      if (incident.step.isNotEmpty) incident.step,
      if (time != null) relativeTime(time),
    ].join(" · ");
    return text.isEmpty ? null : Text(text);
  }

  String _definition(ProcessWait wait) {
    final d = wait.timerDefinition;
    return d == null || d.isEmpty ? "" : " · $d";
  }

  String _kindLabel(String kind) =>
      kind.isEmpty ? "Waiting" : "${kind[0].toUpperCase()}${kind.substring(1)}";
}
