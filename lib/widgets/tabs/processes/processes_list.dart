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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/mixins/resume_refresh_mixin.dart';
import 'package:mobile_app/models/network.dart';
import 'package:mobile_app/models/process.dart';
import 'package:mobile_app/services/haptic_feedback_proxy.dart';
import 'package:mobile_app/services/process_service.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/shared/relative_time.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/shared/grouped_list_tile.dart';
import 'package:mobile_app/widgets/shared/scrollable_empty_state.dart';
import 'package:mobile_app/widgets/shared/sectioned_list_view.dart';
import 'package:mobile_app/widgets/tabs/processes/process_details.dart';
import 'package:mobile_app/widgets/tabs/processes/process_entry.dart';
import 'package:provider/provider.dart';

/// Debug data is one request per running instance; this many at a time keep a
/// large account from opening dozens of connections at once.
const _debugConcurrency = 4;

/// The Processes segment of the Services tab: one row per deployment, grouped
/// by the cloud or gateway it runs on.
class ProcessesList extends StatefulWidget {
  const ProcessesList({super.key});

  @override
  State<ProcessesList> createState() => _ProcessesListState();
}

class _ProcessesListState extends State<ProcessesList>
    with ResumeRefreshMixin {
  List<ProcessEntry>? _entries;
  bool _failed = false;
  StreamSubscription? _refreshSubscription;

  /// Bumped by every load; an answer of an older one is dropped.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _refreshSubscription = AppState().refreshPressed.listen((_) => _refresh());
    _refresh();
  }

  @override
  void dispose() {
    _refreshSubscription?.cancel();
    super.dispose();
  }

  @override
  void onResumed() => _refresh();

  Future<void> _refresh() async {
    final generation = ++_generation;
    // A reload keeps the rows on screen; only the first one shows a spinner.
    if (_entries == null || _failed) {
      setState(() => _failed = false);
    }
    try {
      final loaded = await Future.wait(
          [ProcessService.getDeployments(), ProcessService.getInstances()]);
      if (!mounted || generation != _generation) return;
      final deployments = loaded[0] as List<ProcessDeployment>;
      final latest = latestInstancePerDeployment(
          loaded[1] as List<ProcessInstance>);
      // Debug data of the previous load stays until the new one replaces it.
      final previous = {
        for (final e in _entries ?? const <ProcessEntry>[])
          if (e.instance != null) e.instance!.id: e.debug
      };
      final entries = [
        for (final d in deployments)
          ProcessEntry(
              d,
              latest[d.id],
              latest[d.id] == null ? null : previous[latest[d.id]!.id]),
      ];
      setState(() => _entries = entries);
      unawaited(_loadDebugs(generation));
    } catch (e, s) {
      if (!mounted || generation != _generation) {
        ErrorReporter.log('Could not load processes', e, s);
        return;
      }
      ErrorReporter.report('Could not load processes', e, s);
      setState(() => _failed = true);
    }
  }

  Future<void> _loadDebugs(int generation) async {
    final running = [
      for (final e in _entries ?? const <ProcessEntry>[])
        if (e.instance?.hasDebug ?? false) e.instance!.id
    ];
    await ProcessService.forEachLimited(running, _debugConcurrency, (id) async {
      try {
        final debug = await ProcessService.getDebug(id);
        if (!mounted || generation != _generation) return;
        setState(() {
          _entries = [
            for (final e in _entries!)
              e.instance?.id == id ? e.withDebug(debug) : e
          ];
        });
      } catch (e, s) {
        // A row without next run is still usable; one row's failure is not
        // worth a toast per instance.
        ErrorReporter.log('Could not load process $id', e, s);
      }
    });
  }

  /// Cloud first, then the gateways by name. A hub the app does not know
  /// (not paired or not shared with this account) is titled "Gateway".
  List<ListSection<ProcessEntry>> _sections(List<ProcessEntry> entries) {
    final networks = {for (final n in AppState().networks) n.id: n};
    final byNetwork = <String, List<ProcessEntry>>{};
    for (final e in entries) {
      byNetwork.putIfAbsent(e.deployment.networkId, () => []).add(e);
    }
    String titleOf(String networkId) {
      final Network? network = networks[networkId];
      return network?.name ?? "Gateway";
    }

    final gateways = byNetwork.keys.where((id) => id.isNotEmpty).toList()
      ..sort((a, b) {
        final byName =
            titleOf(a).toLowerCase().compareTo(titleOf(b).toLowerCase());
        return byName != 0 ? byName : a.compareTo(b);
      });
    ListSection<ProcessEntry> section(String networkId, String title) {
      final items = byNetwork[networkId]!
        ..sort((a, b) => a.deployment.name
            .toLowerCase()
            .compareTo(b.deployment.name.toLowerCase()));
      return ListSection<ProcessEntry>(
        id: networkId.isEmpty ? "cloud" : "network:$networkId",
        title: title,
        items: items,
        keyOf: (e) => e.deployment.id,
        itemBuilder: (context, entry, position) => GroupedListTile(
          position: position,
          hairlineInset: GroupedListTile.insetNoLeading,
          child: _ProcessRow(entry: entry),
        ),
      );
    }

    return [
      if (byNetwork.containsKey("")) section("", "Cloud"),
      for (final id in gateways) section(id, titleOf(id)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilds when the networks arrive, which name the gateway sections.
    context.select<AppState, int>((state) => state.networks.length);
    final entries = _entries;
    final Widget body;
    if (entries == null && !_failed) {
      body = const Center(child: DelayedCircularProgressIndicator());
    } else if (entries == null) {
      body = _ErrorState(onRetry: _refresh);
    } else if (entries.isEmpty) {
      body = const ScrollableEmptyState("No Processes");
    } else {
      body = SectionedListView(
        physics: const AlwaysScrollableScrollPhysics(),
        sections: _sections(entries),
      );
    }
    return Scrollbar(
      child: RefreshIndicator(
        onRefresh: () async {
          HapticFeedbackProxy.lightImpact();
          await _refresh();
        },
        child: body,
      ),
    );
  }
}

class _ProcessRow extends StatelessWidget {
  const _ProcessRow({required this.entry});

  final ProcessEntry entry;

  String _subtitle() {
    final instance = entry.instance;
    if (instance == null) {
      final created = entry.deployment.createdAt;
      return created == null ? "Never started" : "Deployed ${relativeTime(created)}";
    }
    final seen = instance.lastSeen;
    final next = instance.isRunning ? entry.debug?.nextTimer() : null;
    return [
      if (seen != null) "Last activity ${relativeTime(seen)}",
      if (next != null) "Next run ${clockOrDate(next)}",
    ].join(" · ");
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = _subtitle();
    return ListTile(
      title: Text(entry.deployment.name),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: ProcessStatusChip(entry),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ProcessDetails(entry)),
      ),
    );
  }
}

/// Inline load error that still scrolls, so a pull reloads as well as the
/// button does.
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraint) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraint.maxHeight),
          child: Center(
            child: Padding(
              padding: Spacing.inset,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, color: context.appColors.error),
                  const SizedBox(height: Spacing.sm),
                  Text("Could not load processes",
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: Spacing.md),
                  FilledButton.tonal(
                      onPressed: onRetry, child: const Text("Retry")),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
