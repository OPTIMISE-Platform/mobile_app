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

// The Automatisierungsvorschläge widget: the open suggestions and the accepted
// automations of its instance, with accept, dismiss, restore, edit and remove.
// The instance is the one the module carries (instance_id); the view is loaded
// by AutomationSuggestionsLoader.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:mobile_app/exceptions/unexpected_status_code_exception.dart';
import 'package:mobile_app/services/automation_engine.dart';
import 'package:mobile_app/services/process_io.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/toast.dart';
import 'package:mobile_app/widgets/tabs/dashboard/dashboard.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/base.dart';
import 'package:mobile_app/widgets/tabs/smart-services/automation_suggestions_load.dart';
import 'package:mobile_app/widgets/tabs/smart-services/automation_suggestions_model.dart';

const _pendingTimeout = Duration(minutes: 2);

/// After an accept or an edit the widget reloads every [_pollInterval] until the
/// module shows it, for at most [_pollLimit].
const _pollInterval = Duration(seconds: 2);
const _pollLimit = Duration(seconds: 30);

/// An accept the procedure has started and that no module shows yet. The
/// module appears when the procedure has run; until then the suggestion is
/// shown as being accepted, and the marker expires after [_pendingTimeout].
class _Pending {
  final ResolvedSuggestion resolved;
  final DateTime since;

  _Pending(this.resolved, this.since);
}

/// An edit of an accepted automation whose new duration the module does not
/// show yet. The row reads "Updating" until then.
class _Update {
  final int? autoOffS;
  final DateTime since;

  _Update(this.autoOffS, this.since);
}

class SmSeAutomationSuggestions extends SmartServiceModuleWidget {
  // Pixel estimates of the rows for the height of the widget, generous so the
  // whole list fits: the dashboard scrolls, the widget does not. A card counts
  // two lines of title and of subtitle; the switch-off row only when offered.
  static const _suggestionCardPx = 172.0;
  static const _autoOffRowPx = 56.0;
  static const _dismissedHeaderPx = 48.0;
  static const _dismissedRowPx = 72.0;
  static const _messageRowPx = 56.0;
  static const _sectionTitlePx = 32.0;
  static const _messageUnits = 3.0;

  AutomationSuggestionsView? _view;
  String? _error;
  final Map<String, _Pending> _pending = {};
  final Map<String, _Update> _updates = {};
  final Set<String> _busy = {};
  Timer? _poll;
  bool _reloading = false;
  DashboardState? _dashboard;

  /// Whether the dismissed section is unfolded. It lives here so [height] knows it.
  bool dismissedExpanded = false;

  @override
  setPreview(bool enabled) => null;

  @override
  double width = 1;

  @override
  Future<void> configure(dynamic data) async {}

  /// The height of the list as laid out, null until the first layout.
  double? _measuredPx;

  /// Takes the laid-out height of the list and redraws the dashboard when it
  /// changed, so the tile follows the content.
  void _measured(BuildContext context, double px) {
    if (_measuredPx != null && (_measuredPx! - px).abs() < 0.5) return;
    _measuredPx = px;
    final dashboard = context.findAncestorStateOfType<DashboardState>();
    if (dashboard != null && dashboard.mounted) dashboard.redraw();
  }

  @override
  double get height {
    final view = _view;
    if (view == null) return _messageUnits;
    final measured = _measuredPx;
    if (measured != null) return measured / heightUnit;
    final cards = _items(view).length;
    final dismissed = view.dismissed.length;
    if (cards + dismissed == 0) return _messageUnits;
    final pixels = 2 * Spacing.md +
        (_error != null ? 2 * _sectionTitlePx : 0) +
        (cards == 0 && _error == null ? _messageRowPx : 0) +
        cards * (_suggestionCardPx + _autoOffRowPx) +
        (dismissed > 0 ? _dismissedHeaderPx + (dismissedExpanded ? dismissed * _dismissedRowPx : 0) : 0);
    return (pixels / heightUnit).ceilToDouble();
  }

  @override
  Widget buildInternal(BuildContext context, bool parentFlexible) {
    final w = _SuggestionsBody(key: ValueKey(instance_id), module: this);
    return parentFlexible ? Expanded(child: w) : w;
  }

  @override
  Future<void> refreshInternal() async {
    try {
      final view = await AutomationSuggestionsLoader.load(instance_id);
      _view = view;
      _error = null;
      final now = DateTime.now();
      final cutoff = now.subtract(_pendingTimeout);
      _pending.removeWhere((id, p) => p.since.isBefore(cutoff) || view.accepted.any((a) => a.suggestionId == id));
      _updates.removeWhere((id, u) => now.difference(u.since) >= _pollLimit || _shows(view, id, u.autoOffS));
    } catch (e, s) {
      ErrorReporter.log("Could not load automation suggestions", e, s);
      _error = _describe(e, "load automation suggestions");
    }
  }

  /// Starts the accept procedure with [autoOffS] seconds of switch-off, or
  /// without one when null.
  Future<void> accept(BuildContext context, ResolvedSuggestion r, int? autoOffS) {
    return _act(context, r.id, "accept the suggestion", () async {
      await AutomationEngineService.startProcedure(instance_id, automationAcceptProcedure, acceptVariablesFor(r, autoOffS));
      _pending[r.id] = _Pending(r, DateTime.now());
      _ensurePolling();
    });
  }

  /// Edits an accepted automation: the accept procedure runs again with the same
  /// suggestion id, and the engine replaces the module under the same key.
  Future<void> update(BuildContext context, ResolvedSuggestion r, int? autoOffS) {
    return _act(context, r.id, "update the automation", () async {
      await AutomationEngineService.startProcedure(instance_id, automationAcceptProcedure, acceptVariablesFor(r, autoOffS));
      _updates[r.id] = _Update(autoOffS, DateTime.now());
      _ensurePolling();
    });
  }

  Future<void> dismiss(BuildContext context, ResolvedSuggestion r) {
    return _act(context, r.id, "dismiss the suggestion", () => ProcessIoService.setVariable(dismissKey(r.id), true, instanceId: instance_id));
  }

  /// Undoes a dismiss by deleting its process-io variable.
  Future<void> restore(BuildContext context, ResolvedSuggestion r) {
    return _act(context, r.id, "restore the suggestion", () => ProcessIoService.deleteVariable(dismissKey(r.id)));
  }

  Future<void> remove(BuildContext context, AcceptedSuggestion a) async {
    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog.adaptive(
        title: const Text("Remove this automation?"),
        content: const Text("The automation stops running. The suggestion is offered again."),
        actions: [
          TextButton(child: const Text("Cancel"), onPressed: () => Navigator.pop(dialogContext, false)),
          TextButton(child: const Text("Remove"), onPressed: () => Navigator.pop(dialogContext, true)),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _act(context, a.suggestionId, "remove the automation", () async {
      await AutomationEngineService.deleteModule(a.moduleId);
      _pending.remove(a.suggestionId);
      _updates.remove(a.suggestionId);
    });
  }

  /// Runs one action: marks [busyId] busy, redraws, runs [op], then loads the
  /// view again without the refresh spinner, so the list stays in place.
  Future<void> _act(BuildContext context, String busyId, String what, Future<void> Function() op) async {
    final dashboard = context.findAncestorStateOfType<DashboardState>();
    _dashboard = dashboard;
    _busy.add(busyId);
    dashboard?.redraw();
    try {
      await op();
    } catch (e, s) {
      ErrorReporter.log("Could not $what", e, s);
      Toast.showToastNoContext(_describe(e, what));
    } finally {
      _busy.remove(busyId);
    }
    await _reload();
    dashboard?.redraw();
  }

  /// Loads the view as refresh does, but without its lock: refresh replaces the
  /// whole body with a spinner, which made the list jump on every poll.
  Future<void> _reload() async {
    if (_reloading) return;
    _reloading = true;
    try {
      await refreshInternal();
    } finally {
      _reloading = false;
    }
  }

  /// Starts the reload timer when something waits for the module, and does
  /// nothing when the timer runs already.
  void _ensurePolling() {
    if (_poll != null || !_stillPolling(DateTime.now())) return;
    _poll = Timer.periodic(_pollInterval, (_) {
      _pollOnce();
    });
  }

  bool _stillPolling(DateTime now) =>
      _updates.values.any((u) => now.difference(u.since) < _pollLimit) ||
      _pending.values.any((p) => now.difference(p.since) < _pollLimit);

  Future<void> _pollOnce() async {
    await _reload();
    final dashboard = _dashboard;
    if (dashboard != null && dashboard.mounted) dashboard.redraw();
    if (!_stillPolling(DateTime.now())) {
      _poll?.cancel();
      _poll = null;
    }
  }

  /// A 403 is named as such, because it is the answer while the policies for
  /// the automation-engine are not granted to the user.
  String _describe(Object e, String action) {
    if (e is UnexpectedStatusCodeException && e.code == 403) {
      return "Not allowed to $action (403 Forbidden).";
    }
    if (e is UnexpectedStatusCodeException && e.code == 404 && action == "load automation suggestions") {
      // The instance of this widget was deleted; the dashboard still holds the widget.
      return "This smart service was deleted. Remove this widget.";
    }
    return "Could not $action: $e";
  }

  /// Open and accepted suggestions in one list, in the order of the export, so
  /// a card keeps its place when it is accepted and only changes its state.
  /// Accepted ones the export no longer lists follow at the end.
  List<_Item> _items(AutomationSuggestionsView view) {
    final items = <_Item>[];
    final placed = <String>{};
    for (final s in view.snapshot?.suggestions ?? const <Suggestion>[]) {
      final accepted = view.accepted.where((a) => a.suggestionId == s.id).firstOrNull;
      final open = view.suggestions.where((r) => r.id == s.id).firstOrNull;
      if (accepted != null) {
        items.add(_Item(accepted: accepted));
      } else if (open != null) {
        items.add(_Item(open: open));
      } else {
        continue;
      }
      placed.add(s.id);
    }
    for (final a in view.accepted) {
      if (!placed.contains(a.suggestionId)) items.add(_Item(accepted: a));
    }
    return items;
  }

  /// Whether the module shows the switch-off [autoOffS] for [id].
  static bool _shows(AutomationSuggestionsView view, String id, int? autoOffS) =>
      view.accepted.any((a) => a.suggestionId == id && a.autoOffKnown && a.autoOffS == autoOffS);
}

/// The list of the widget. Holds what the user typed for the switch-off, so
/// the edits survive a redraw; a refresh replaces this body with a spinner and
/// resets them.
class _SuggestionsBody extends StatefulWidget {
  const _SuggestionsBody({required super.key, required this.module});

  final SmSeAutomationSuggestions module;

  @override
  State<_SuggestionsBody> createState() => _SuggestionsBodyState();
}

/// The switch-off the user chose for one suggestion: whether it is on, and
/// the duration as typed.
class _AutoOffChoice {
  bool on;
  String text;

  _AutoOffChoice(this.on, this.text);
}

class _SuggestionsBodyState extends State<_SuggestionsBody> {
  final Map<String, _AutoOffChoice> _choices = {};

  /// Starts with the switch on and the duration of the suggestion, when it
  /// proposes one.
  _AutoOffChoice _choiceFor(ResolvedSuggestion s) => _choices.putIfAbsent(
        s.id,
        () => _AutoOffChoice(s.suggestion.autoOffS != null, s.suggestion.autoOffS?.toString() ?? ""),
      );

  @override
  Widget build(BuildContext context) {
    final m = widget.module;
    final view = m._view;
    if (view == null) return _message(m._error ?? "No automation suggestions loaded.");

    final items = m._items(view);
    final dismissed = view.dismissed;
    final nothingOpen = items.isEmpty;
    if (nothingOpen && dismissed.isEmpty) {
      return _message(m._error ??
          (view.snapshot == null ? "No suggestions yet. The service has not produced a list." : "No suggestions."));
    }

    // The list lays out at its natural height and reports it; the widget then
    // takes exactly that height, so nothing scrolls inside the dashboard and no
    // space stays empty below.
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: _MeasureSize(
        onChange: (size) => m._measured(context, size.height),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (m._error != null)
                Padding(padding: const EdgeInsets.only(bottom: Spacing.sm), child: Text(m._error!)),
              if (nothingOpen && m._error == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.sm),
                  child: Text(view.snapshot == null
                      ? "No suggestions yet. The service has not produced a list."
                      : "No suggestions."),
                ),
              for (final item in items)
                item.accepted != null ? _acceptedCard(context, item.accepted!) : _suggestionRow(context, item.open!),
              if (dismissed.isNotEmpty) _dismissedSection(context, dismissed),
            ],
          ),
        ),
      ),
    );
  }

  /// An accepted suggestion: the same card as an open one, same height, with its
  /// state where the open card has the switch-off chip, and Remove and Edit.
  Widget _acceptedCard(BuildContext context, AcceptedSuggestion a) {
    final m = widget.module;
    final theme = Theme.of(context);
    final resolved = a.resolved;
    final removing = m._busy.contains(a.suggestionId);
    final updating = m._updates.containsKey(a.suggestionId);
    final editable = resolved != null && resolved.canAutoOff;
    return _card(
      context,
      title: resolved?.label ?? "Automation ${a.suggestionId.substring(0, 8)}",
      subtitle: resolved == null ? "No longer suggested" : _suggestionSubtitle(resolved),
      middle: Row(children: [
        Icon(Icons.circle, size: 10, color: theme.colorScheme.primary),
        const SizedBox(width: Spacing.xs),
        Expanded(child: Text(_acceptedState(m, a), style: theme.textTheme.bodyMedium)),
      ]),
      actions: [
        OutlinedButton(
          onPressed: removing || updating ? null : () => m.remove(context, a),
          child: _BusyLabel(busy: removing, child: const Text("Remove")),
        ),
        if (editable) ...[
          const SizedBox(width: Spacing.sm),
          FilledButton(
            onPressed: removing || updating ? null : () => _editAccepted(context, a),
            child: _BusyLabel(busy: updating, child: const Text("Edit")),
          ),
        ],
      ],
    );
  }

  /// The tinted card every item uses. [middle] sits in a row of fixed height,
  /// so an open card and an accepted one are equally tall.
  Widget _card(BuildContext context,
      {required String title, required String subtitle, required Widget middle, required List<Widget> actions}) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHigh,
      margin: const EdgeInsets.only(bottom: Spacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: Spacing.xxs),
            Text(subtitle, style: theme.textTheme.bodySmall),
            SizedBox(height: _middleRowPx, child: Align(alignment: Alignment.centerLeft, child: middle)),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
          ],
        ),
      ),
    );
  }

  /// The dismissed suggestions behind a header that folds them out.
  Widget _dismissedSection(BuildContext context, List<ResolvedSuggestion> dismissed) {
    final m = widget.module;
    final expanded = m.dismissedExpanded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() => m.dismissedExpanded = !expanded);
            context.findAncestorStateOfType<DashboardState>()?.redraw();
          },
          child: SizedBox(
            height: SmSeAutomationSuggestions._dismissedHeaderPx,
            child: Row(
              children: [
                Text("Dismissed (${dismissed.length})", style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(width: Spacing.xxs),
                Icon(expanded ? Icons.expand_less : Icons.expand_more),
              ],
            ),
          ),
        ),
        if (expanded) for (final d in dismissed) _dismissedRow(context, d),
      ],
    );
  }

  Widget _dismissedRow(BuildContext context, ResolvedSuggestion d) {
    final m = widget.module;
    final theme = Theme.of(context);
    return SizedBox(
      height: SmSeAutomationSuggestions._dismissedRowPx,
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                Text(_windowText(d.suggestion.window),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          TextButton(
            onPressed: m._busy.contains(d.id) ? null : () => m.restore(context, d),
            child: _BusyLabel(busy: m._busy.contains(d.id), child: const Text("Restore")),
          ),
        ],
      ),
    );
  }

  /// One suggestion as a tinted card: text, the switch-off as a chip that
  /// toggles it and opens the duration on its pencil, and labelled buttons.
  Widget _suggestionRow(BuildContext context, ResolvedSuggestion s) {
    final m = widget.module;
    final theme = Theme.of(context);
    final busy = m._busy.contains(s.id) || m._pending.containsKey(s.id);
    final offered = s.offersAutoOff;
    final choice = _choiceFor(s);
    final seconds = parseAutoOffSeconds(choice.text);
    final switchOff = offered && choice.on;
    final canAccept = !busy && (!switchOff || seconds != null);
    return _card(
      context,
      title: s.label,
      subtitle: _suggestionSubtitle(s),
      middle: !offered
          ? const SizedBox.shrink()
          : Row(children: [
                // On and off differ in text, icon and colour, not only in
                // the chip's selection tint.
                FilterChip(
                  avatar: choice.on ? null : const Icon(Icons.timer_off_outlined, size: 18),
                  label: Text(choice.on ? "Off after ${seconds ?? choice.text} s" : "No auto-off"),
                  selected: choice.on,
                  showCheckmark: true,
                  selectedColor: theme.colorScheme.primaryContainer,
                  labelStyle: TextStyle(
                    color: choice.on ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurfaceVariant,
                  ),
                  onSelected: busy ? null : (v) => setState(() => choice.on = v),
                ),
                IconButton(
                  tooltip: "Change duration",
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: busy ? null : () => _editSeconds(context, choice),
                ),
              ]),
      actions: [
        OutlinedButton(
          onPressed: busy ? null : () => m.dismiss(context, s),
          child: const Text("Dismiss"),
        ),
        const SizedBox(width: Spacing.sm),
        FilledButton(
          onPressed: canAccept ? () => m.accept(context, s, switchOff ? seconds : null) : null,
          child: _BusyLabel(busy: busy, child: const Text("Accept")),
        ),
      ],
    );
  }

  /// Asks for the switch-off duration; a valid entry also turns the switch-off on.
  Future<void> _editSeconds(BuildContext context, _AutoOffChoice choice) async {
    var text = choice.text;
    final result = await showAdaptiveDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final valid = parseAutoOffSeconds(text) != null;
          return AlertDialog.adaptive(
            title: const Text("Switch off after"),
            content: Material(
              type: MaterialType.transparency,
              child: TextFormField(
                initialValue: text,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  suffixText: "s",
                  errorText: valid ? null : "$autoOffMinSeconds–$autoOffMaxSeconds s",
                ),
                onChanged: (v) => setDialogState(() => text = v),
              ),
            ),
            actions: [
              TextButton(child: const Text("Cancel"), onPressed: () => Navigator.pop(dialogContext)),
              TextButton(
                onPressed: valid ? () => Navigator.pop(dialogContext, text) : null,
                child: const Text("Set"),
              ),
            ],
          );
        },
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      choice.text = result.trim();
      choice.on = true;
    });
  }

  /// Edits the switch-off of an accepted automation. Starts with the duration the
  /// module carries, or with the one of the suggestion when the module carries none
  /// readable. Save runs the accept procedure again with the chosen duration.
  Future<void> _editAccepted(BuildContext context, AcceptedSuggestion a) async {
    final r = a.resolved;
    if (r == null) return;
    final initial = a.autoOffKnown ? a.autoOffS : r.suggestion.autoOffS;
    var on = initial != null;
    var text = initial?.toString() ?? "";
    final result = await showAdaptiveDialog<({int? seconds})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final valid = parseAutoOffSeconds(text) != null;
          return AlertDialog.adaptive(
            title: const Text("Automation"),
            content: Material(
              type: MaterialType.transparency,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Switch off automatically"),
                    value: on,
                    onChanged: (v) => setDialogState(() => on = v),
                  ),
                  TextFormField(
                    initialValue: text,
                    enabled: on,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      suffixText: "s",
                      errorText: on && !valid ? "$autoOffMinSeconds–$autoOffMaxSeconds s" : null,
                    ),
                    onChanged: (v) => setDialogState(() => text = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(child: const Text("Cancel"), onPressed: () => Navigator.pop(dialogContext)),
              TextButton(
                onPressed: !on || valid
                    ? () => Navigator.pop(dialogContext, (seconds: on ? parseAutoOffSeconds(text) : null))
                    : null,
                child: const Text("Save"),
              ),
            ],
          );
        },
      ),
    );
    if (result == null || !context.mounted) return;
    await widget.module.update(context, r, result.seconds);
  }

  // A list, so a long error text scrolls inside the fixed height of the widget.
  Widget _message(String text) => ListView(
        padding: const EdgeInsets.all(Spacing.md),
        children: [Text(text, textAlign: TextAlign.center)],
      );
}

/// "Active · off after 140 s", "Active · no auto-off", or "Updating" while an
/// edit is pending. Without a readable duration only "Active".
String _acceptedState(SmSeAutomationSuggestions m, AcceptedSuggestion a) {
  if (m._updates.containsKey(a.suggestionId)) return "Updating";
  if (!a.autoOffKnown) return "Active";
  return a.autoOffS != null ? "Active · off after ${a.autoOffS} s" : "Active · no auto-off";
}

/// "19:00–02:00 · Mon–Fri".
String _windowText(SuggestionWindow w) {
  final parts = <String>["${w.from}–${w.to}"];
  final days = w.weekdays.toSet();
  if (days.length == 5 && days.every((d) => d < 5)) {
    parts.add("Mon–Fri");
  } else if (days.length == 2 && days.every((d) => d >= 5)) {
    parts.add("Sat–Sun");
  }
  return parts.join(" · ");
}

/// "19:00–02:00 · Mon–Fri · follows in 31 % of 291 triggers".
String _suggestionSubtitle(ResolvedSuggestion r) {
  final s = r.suggestion;
  final pct = (s.stats.confidence * 100).round();
  return "${_windowText(s.window)} · follows in $pct % of ${s.stats.occurrences} triggers";
}

/// A spinner of icon size, for a button that is busy.
class _SmallSpinner extends StatelessWidget {
  const _SmallSpinner();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2));
}

/// The label of a button, replaced by a small spinner while busy. The label
/// keeps its space, so the button keeps its size and the row does not move.
class _BusyLabel extends StatelessWidget {
  const _BusyLabel({required this.busy, required this.child});

  final bool busy;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
        alignment: Alignment.center,
        children: [
          Visibility(visible: !busy, maintainSize: true, maintainAnimation: true, maintainState: true, child: child),
          if (busy) const _SmallSpinner(),
        ],
      );
}

/// One card of the list: an open suggestion or an accepted one.
class _Item {
  final ResolvedSuggestion? open;
  final AcceptedSuggestion? accepted;

  _Item({this.open, this.accepted});
}

const _middleRowPx = 56.0;

/// Reports the size of [child] after layout whenever it changes.
class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({required this.onChange, required Widget super.child});

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMeasureSize(onChange);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasureSize renderObject) => renderObject.onChange = onChange;
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize(this.onChange);

  ValueChanged<Size> onChange;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _last) return;
    _last = size;
    // after the frame: the callback redraws the dashboard, which must not
    // happen during layout
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(size));
  }
}
