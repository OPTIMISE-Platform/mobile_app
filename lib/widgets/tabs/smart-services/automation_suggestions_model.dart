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

// Model of the Automatisierungsvorschläge smart service: parsing of the export
// row, resolution of the targets against the device types, labels and the
// variables of the accept procedure. Pure Dart, no I/O.

import 'dart:convert';

import 'package:mobile_app/models/content.dart';
import 'package:mobile_app/models/content_variable.dart';
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/models/function.dart';
import 'package:mobile_app/models/service.dart';
import 'package:mobile_app/services/automation_engine.dart';

const automationExportModuleType = "export";
const automationProcessDeploymentModuleType = "process_deployment";
const automationAcceptProcedure = "accept_suggestion";
const automationPowerKind = "power";
const automationSuggestionKeyPrefix = "suggestion:";
const automationDismissKeyPrefix = "automation-suggester.dismissed.";

/// Bounds of the auto-off duration in whole seconds: the engine minimum and the
/// upper limit of the app.
const autoOffMinSeconds = 5;
const autoOffMaxSeconds = 3600;

const setDeviceOnFunctionId = "urn:infai:ses:controlling-function:79e7914b-f303-4a7d-90af-dee70db05fd9";
const setDeviceOffFunctionId = "urn:infai:ses:controlling-function:2f35150b-9df7-4cad-95bc-165fa00219fd";

/// Get-Binary State and its concept. A measured function of this function or
/// concept is binary.
const getBinaryStateFunctionId = "urn:infai:ses:measuring-function:2c284729-9bcd-4cde-b00c-1edbdaaab724";
const binaryStateConceptId = "urn:infai:ses:concept:ebfeabb3-50f0-44bd-b06e-95eb52df484e";

String dismissKey(String suggestionId) => "$automationDismissKeyPrefix$suggestionId";

String suggestionKey(String suggestionId) => "$automationSuggestionKeyPrefix$suggestionId";

class SuggestionTrigger {
  final String deviceId, serviceId, path, kind;
  final String? from, to;

  /// Only for a `power` trigger: the thresholds in watts and the hold time in
  /// seconds. Null for every other kind.
  final num? onAboveW, offBelowW, holdS;

  SuggestionTrigger(this.deviceId, this.serviceId, this.path, this.kind, this.from, this.to,
      {this.onAboveW, this.offBelowW, this.holdS});
}

class SuggestionWindow {
  final String from, to, tz;
  final List<int> weekdays;

  SuggestionWindow(this.from, this.to, this.weekdays, this.tz);
}

class SuggestionTarget {
  final String deviceId, serviceId, path;
  // The export carries no function id; the client resolves it from the device type.
  final String? functionId;
  // A bool for a binary target, otherwise the median of the level.
  final dynamic value;

  SuggestionTarget(this.deviceId, this.serviceId, this.path, this.functionId, this.value);
}

class SuggestionStats {
  final int occurrences, hits;
  final double confidence;

  SuggestionStats(this.occurrences, this.hits, this.confidence);
}

class Suggestion {
  final String id;
  final SuggestionTrigger trigger;
  final SuggestionWindow window;
  final List<SuggestionTarget> targets;
  final int? autoOffS;
  final SuggestionStats stats;

  Suggestion(this.id, this.trigger, this.window, this.targets, this.autoOffS, this.stats);
}

class ExportSnapshot {
  final String version, trainedAt;
  final List<Suggestion> suggestions;

  /// Entries that could not be read and were left out.
  final int skipped;

  ExportSnapshot(this.version, this.trainedAt, this.suggestions, {this.skipped = 0});
}

/// A target with its command resolved: the control service, the control
/// function and the input characteristic. A binary target that auto-switches
/// off also carries the off command, which may sit on another service of the
/// device type.
class ResolvedTarget {
  final String deviceId, serviceId, functionId, characteristicId;
  final dynamic value;
  final String? offServiceId, offFunctionId, offCharacteristicId;
  final dynamic offValue;

  ResolvedTarget(this.deviceId, this.serviceId, this.functionId, this.characteristicId, this.value, this.offServiceId, this.offFunctionId,
      this.offCharacteristicId, this.offValue);
}

class ResolvedSuggestion {
  final Suggestion suggestion;

  /// Only the targets that resolved. Empty when none did.
  final List<ResolvedTarget> targets;
  final String label;

  ResolvedSuggestion(this.suggestion, this.targets, this.label);

  String get id => suggestion.id;

  /// Whether a target that switches on has a resolved Set Device Off. Only then
  /// the switch-off can run; without it no target carries one.
  bool get canAutoOff => targets.any((t) => t.value == true && t.offFunctionId != null);

  /// Whether the user is offered the switch-off: the suggestion proposes one and
  /// [canAutoOff] holds.
  bool get offersAutoOff => suggestion.autoOffS != null && canAutoOff;
}

/// The auto-off duration the user typed, or null when it is not a whole number
/// of seconds within [autoOffMinSeconds] to [autoOffMaxSeconds].
int? parseAutoOffSeconds(String text) {
  final trimmed = text.trim();
  if (!RegExp(r"^\d+$").hasMatch(trimmed)) return null;
  final seconds = int.tryParse(trimmed);
  if (seconds == null || seconds < autoOffMinSeconds || seconds > autoOffMaxSeconds) return null;
  return seconds;
}

/// Reads the `suggestions` value of the newest export: the JSON object with
/// `version`, `trained_at` and `suggestions`, as text or already decoded.
/// Throws [FormatException] when it does not have that shape.
ExportSnapshot parseExportSuggestions(dynamic raw) {
  final decoded = raw is String ? json.decode(raw) : raw;
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException("suggestions is not a JSON object");
  }
  final list = decoded["suggestions"];
  if (list is! List) {
    throw const FormatException("suggestions has no list");
  }
  final version = decoded["version"]?.toString() ?? "";
  final trainedAt = decoded["trained_at"]?.toString() ?? "";
  final suggestions = <Suggestion>[];
  var skipped = 0;
  for (final entry in list) {
    try {
      suggestions.add(_suggestionFromJson(entry as Map<String, dynamic>));
    } on Object {
      // One broken entry must not hide the rest of the list.
      skipped++;
    }
  }
  return ExportSnapshot(version, trainedAt, suggestions, skipped: skipped);
}

/// Whether the process-io variable of a dismissed suggestion exists. A failed
/// lookup means nothing is dismissed, so the suggestion stays visible.
Future<bool> isDismissed(Future<Object?> Function() lookup, {void Function(Object error, StackTrace stack)? onError}) async {
  try {
    return await lookup() != null;
  } on Object catch (e, s) {
    onError?.call(e, s);
    return false;
  }
}

Suggestion _suggestionFromJson(Map<String, dynamic> j) {
  final t = j["trigger"] as Map<String, dynamic>;
  final w = j["window"] as Map<String, dynamic>;
  final s = j["stats"] as Map<String, dynamic>;
  final kind = t["kind"] as String;
  // A power trigger without its thresholds throws here, so the entry is skipped.
  final power = kind == automationPowerKind;
  num number(String key) => t[key] as num;
  return Suggestion(
    j["id"] as String,
    SuggestionTrigger(t["device_id"] as String, t["service_id"] as String, t["path"] as String, kind,
        t["from"] as String?, t["to"] as String?,
        onAboveW: power ? number("on_above_w") : null,
        offBelowW: power ? number("off_below_w") : null,
        holdS: power ? number("hold_s") : null),
    SuggestionWindow(w["from"] as String, w["to"] as String, (w["weekdays"] as List<dynamic>).map((d) => d as int).toList(), w["tz"] as String),
    (j["targets"] as List<dynamic>)
        .map((x) {
          final m = x as Map<String, dynamic>;
          return SuggestionTarget(m["device_id"] as String, m["service_id"] as String, m["path"] as String, m["function_id"] as String?, m["value"]);
        })
        .toList(),
    (j["auto_off_s"] as num?)?.toInt(),
    SuggestionStats((s["occurrences"] as num).toInt(), (s["hits"] as num).toInt(), (s["confidence"] as num).toDouble()),
  );
}

/// Resolves [suggestion] against the device types of its devices. A target
/// whose device has no type, or whose command cannot be resolved, is left
/// out. [names] maps device ids to display names, [functions] function ids to
/// their concept.
ResolvedSuggestion resolveSuggestion(
  Suggestion suggestion, {
  required Map<String, DeviceType> typesByDevice,
  required Map<String, PlatformFunction> functions,
  required Map<String, String> names,
}) {
  final resolved = <ResolvedTarget>[];
  for (final target in suggestion.targets) {
    final type = typesByDevice[target.deviceId];
    if (type == null) continue;
    final r = resolveTarget(target, suggestion.autoOffS, type, functions);
    if (r != null) resolved.add(r);
  }
  final labelTargets = resolved.isNotEmpty
      ? [for (final r in resolved) (deviceId: r.deviceId, value: r.value)]
      : [for (final t in suggestion.targets) (deviceId: t.deviceId, value: t.value)];
  return ResolvedSuggestion(suggestion, resolved, suggestionLabel(suggestion.trigger, labelTargets, names));
}

/// The command of one target, or null when it cannot be resolved.
///
/// A target is binary when its measured function is Get-Binary State or has
/// its concept; without a resolvable measured function the bool value decides.
/// A binary target only takes a bool. Any other value is hidden, so no text is ever sent
/// to `Set Device On` or `Set Device Off`.
///
/// A binary target is switched with the on or off function. An auto-off
/// resolves `Set Device Off` on its own, on any service of the device type in
/// the same preference order. Without such a function the target stays, with
/// no switch-off part; the suggestion then offers no auto-off ([ResolvedSuggestion.canAutoOff]).
///
/// Any other target takes the controlling function of the measured function's
/// concept, on the service of the target, else on a service of its group. A
/// bool value is hidden there as well.
ResolvedTarget? resolveTarget(SuggestionTarget target, int? autoOffS, DeviceType type, Map<String, PlatformFunction> functions) {
  final measured = _serviceById(type, target.serviceId);
  final measuredLeaf = measured == null ? null : _variableAt(measured.outputs, _channelPath(target.path));
  final measuredFunction = measuredLeaf?.function_id;
  final measuredConcept = measuredFunction == null ? null : functions[measuredFunction]?.concept_id;
  final binary = measuredLeaf == null ? target.value is bool : _isBinaryState(measuredFunction, measuredConcept);

  if (binary) {
    final value = target.value;
    if (value is! bool) return null;
    final control = _firstInput(type, target.serviceId, value ? setDeviceOnFunctionId : setDeviceOffFunctionId);
    if (control == null) return null;
    if (!value || autoOffS == null) {
      return ResolvedTarget(target.deviceId, control.serviceId, control.functionId, control.characteristicId, value, null, null, null, null);
    }
    final off = _firstInput(type, target.serviceId, setDeviceOffFunctionId);
    return ResolvedTarget(target.deviceId, control.serviceId, control.functionId, control.characteristicId, value,
        off?.serviceId, off?.functionId, off?.characteristicId, off == null ? null : false);
  }

  if (target.value is bool || measuredLeaf == null || measuredConcept == null) return null;
  final candidates = <_Control>[];
  for (final service in _servicesInPreference(type, target.serviceId)) {
    for (final leaf in _inputLeaves(service)) {
      final fn = leaf.function_id;
      if (fn == null || leaf.characteristic_id == null || !fn.startsWith(controllingFunctionPrefix)) continue;
      if (functions[fn]?.concept_id != measuredConcept) continue;
      candidates.add(_Control(service.id, fn, leaf.characteristic_id!, leaf.effectiveAspects));
    }
  }
  final aspects = measuredLeaf.effectiveAspects.join(",");
  final sameAspects = candidates.where((c) => c.aspects.join(",") == aspects);
  final control = sameAspects.isNotEmpty ? sameAspects.first : (candidates.isNotEmpty ? candidates.first : null);
  if (control == null) return null;
  return ResolvedTarget(target.deviceId, control.serviceId, control.functionId, control.characteristicId, target.value, null, null, null, null);
}

/// Decided by the function id or the concept. The platform leaves the concept
/// of `Set Device On`/`Off` empty, so comparing against theirs never matches.
bool _isBinaryState(String? functionId, String? conceptId) =>
    functionId == getBinaryStateFunctionId || (conceptId != null && conceptId == binaryStateConceptId);

/// The export carries the analytics prefix `value.` on every path, the device
/// type does not. Exactly one leading `value.` goes; the device type may use
/// `value` as its root name too, so the rest is never stripped again.
String _channelPath(String path) => path.startsWith("value.") ? path.substring("value.".length) : path;

/// "Stehlampe aus → Licht EG an" as the deployment is named.
String suggestionLabel(SuggestionTrigger trigger, List<({String deviceId, dynamic value})> targets, Map<String, String> names) {
  final head = "${_nameOf(names, trigger.deviceId)} ${_triggerWord(trigger)}";
  if (targets.isEmpty) return head;
  final tail = targets.map((t) => "${_nameOf(names, t.deviceId)} ${_targetWord(t.value)}").join(", ");
  return "$head → $tail";
}

/// The variables of the accept procedure for [resolved], with the auto-off the
/// suggestion proposes when it is offered. Every value is a string; the JSON
/// values are encoded as JSON text.
Map<String, String> acceptVariables(ResolvedSuggestion resolved) =>
    acceptVariablesFor(resolved, resolved.offersAutoOff ? resolved.suggestion.autoOffS : null);

/// The variables of the accept procedure for [resolved] with [autoOffS] seconds
/// of auto-off, or without auto-off when null. Without auto-off every target
/// has null `off_*` fields and `auto_off_s` is empty.
///
/// Throws [ArgumentError] when [autoOffS] is outside the bounds, or when no
/// target has a resolved Set Device Off.
Map<String, String> acceptVariablesFor(ResolvedSuggestion resolved, int? autoOffS) {
  if (autoOffS != null) {
    if (autoOffS < autoOffMinSeconds || autoOffS > autoOffMaxSeconds) {
      throw ArgumentError.value(autoOffS, "autoOffS", "must be $autoOffMinSeconds to $autoOffMaxSeconds seconds");
    }
    if (!resolved.canAutoOff) {
      throw ArgumentError.value(autoOffS, "autoOffS", "no target has a resolved Set Device Off");
    }
  }
  final s = resolved.suggestion;
  final t = s.trigger;
  final w = s.window;
  return {
    "suggestion_id": s.id,
    "label": resolved.label,
    "trigger": json.encode({
      "device_id": t.deviceId,
      "service_id": t.serviceId,
      "path": t.path,
      "kind": t.kind,
      "from": t.from,
      "to": t.to,
      if (t.kind == automationPowerKind) ...{
        "on_above_w": t.onAboveW,
        "off_below_w": t.offBelowW,
        "hold_s": t.holdS,
      },
    }),
    "window": json.encode({"from": w.from, "to": w.to, "weekdays": w.weekdays, "tz": w.tz}),
    "targets": json.encode([
      for (final r in resolved.targets)
        {
          "device_id": r.deviceId,
          "service_id": r.serviceId,
          "function_id": r.functionId,
          "characteristic_id": r.characteristicId,
          "value": r.value,
          "off_service_id": autoOffS == null ? null : r.offServiceId,
          "off_function_id": autoOffS == null ? null : r.offFunctionId,
          "off_characteristic_id": autoOffS == null ? null : r.offCharacteristicId,
          "off_value": autoOffS == null ? null : r.offValue,
        }
    ]),
    "auto_off_s": autoOffS?.toString() ?? "",
  };
}

/// The suggestion ids that the instance has accepted, with the module that
/// carries each of them.
Map<String, String> acceptedModules(List<AutomationModule> modules) {
  final result = <String, String>{};
  for (final m in modules) {
    for (final key in m.keys) {
      if (key.startsWith(automationSuggestionKeyPrefix)) {
        result[key.substring(automationSuggestionKeyPrefix.length)] = m.id;
      }
    }
  }
  return result;
}

/// The auto-off an accepted module carries in its module data: the seconds, or
/// null for none. [known] is false when the module predates the field, or the
/// value is neither a number nor null; then no duration is shown.
({int? seconds, bool known}) moduleAutoOff(AutomationModule module) {
  final data = module.moduleData;
  if (data == null || !data.containsKey("auto_off_s")) return (seconds: null, known: false);
  final value = data["auto_off_s"];
  if (value == null) return (seconds: null, known: true);
  if (value is num) return (seconds: value.toInt(), known: true);
  return (seconds: null, known: false);
}

/// Splits the candidates of the newest export into the open and the dismissed
/// suggestions. Both lists hold only suggestions with at least one resolved
/// target. An accepted candidate is in neither list.
({List<ResolvedSuggestion> open, List<ResolvedSuggestion> dismissed}) splitSuggestions({
  required List<Suggestion> candidates,
  required Set<String> accepted,
  required Set<String> dismissed,
  required Map<String, ResolvedSuggestion> resolvedById,
}) {
  final open = <ResolvedSuggestion>[];
  final gone = <ResolvedSuggestion>[];
  for (final s in candidates) {
    if (accepted.contains(s.id)) continue;
    final r = resolvedById[s.id];
    if (r == null || r.targets.isEmpty) continue;
    (dismissed.contains(s.id) ? gone : open).add(r);
  }
  return (open: open, dismissed: gone);
}

class _Control {
  final String serviceId, functionId, characteristicId;
  final List<String> aspects;

  _Control(this.serviceId, this.functionId, this.characteristicId, this.aspects);
}

Service? _serviceById(DeviceType type, String serviceId) {
  for (final s in type.services) {
    if (s.id == serviceId) return s;
  }
  return null;
}

/// The services to look at for a control: the service itself, then the
/// services of its service group, then the rest.
List<Service> _servicesInPreference(DeviceType type, String serviceId) {
  final measured = _serviceById(type, serviceId);
  final group = measured?.service_group_key;
  final first = type.services.where((s) => s.id == serviceId).toList();
  final sameGroup = type.services.where((s) => s.id != serviceId && group != null && s.service_group_key == group).toList();
  final rest = type.services.where((s) => !first.contains(s) && !sameGroup.contains(s)).toList();
  return [...first, ...sameGroup, ...rest];
}

_Control? _firstInput(DeviceType type, String serviceId, String functionId) {
  for (final service in _servicesInPreference(type, serviceId)) {
    final c = _firstInputInService(type, service.id, functionId);
    if (c != null) return c;
  }
  return null;
}

_Control? _firstInputInService(DeviceType type, String serviceId, String functionId) {
  final service = _serviceById(type, serviceId);
  if (service == null) return null;
  for (final leaf in _inputLeaves(service)) {
    if (leaf.function_id == functionId && leaf.characteristic_id != null) {
      return _Control(service.id, functionId, leaf.characteristic_id!, leaf.effectiveAspects);
    }
  }
  return null;
}

/// Every content variable with a function on the inputs of [service].
List<ContentVariable> _inputLeaves(Service service) {
  final out = <ContentVariable>[];
  void collect(ContentVariable cv) {
    if (cv.function_id != null) out.add(cv);
    for (final sub in cv.sub_content_variables ?? const <ContentVariable>[]) {
      collect(sub);
    }
  }
  for (final input in service.inputs ?? const []) {
    collect(input.content_variable);
  }
  return out;
}

/// The content variable at a dotted [path] such as `value.state`, where each
/// segment is a variable name, counted from the top level of [contents].
ContentVariable? _variableAt(List<Content>? contents, String path) {
  var level = <ContentVariable>[for (final c in contents ?? const <Content>[]) c.content_variable];
  ContentVariable? current;
  for (final segment in path.split(".")) {
    current = null;
    for (final cv in level) {
      if (cv.name == segment) {
        current = cv;
        break;
      }
    }
    if (current == null) return null;
    level = current.sub_content_variables ?? const [];
  }
  return current;
}

String _nameOf(Map<String, String> names, String deviceId) => names[deviceId] ?? deviceId;

String _triggerWord(SuggestionTrigger t) {
  final to = t.to ?? "";
  return switch (t.kind) {
    "binary" => switch (to) {
        "on" => "an",
        "off" => "aus",
        _ => to,
      },
    "power" => switch (to) {
        "on" when t.onAboveW != null => "an (> ${t.onAboveW} W)",
        "off" when t.offBelowW != null => "aus (< ${t.offBelowW} W)",
        _ => to,
      },
    "contact" => switch (to) {
        "open" => "offen",
        "closed" => "geschlossen",
        _ => to,
      },
    "position" => switch (to) {
        "up" => "hoch",
        "down" => "runter",
        _ => to,
      },
    _ => to,
  };
}

String _targetWord(dynamic value) {
  if (value is bool) return value ? "an" : "aus";
  return "auf $value";
}
