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
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/models/smart_service.dart';
import 'package:mobile_app/services/automation_engine.dart';
import 'package:mobile_app/services/db_query.dart';
import 'package:mobile_app/services/device_types.dart';
import 'package:mobile_app/services/devices.dart';
import 'package:mobile_app/services/functions.dart';
import 'package:mobile_app/services/process_io.dart';
import 'package:mobile_app/services/smart_service.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/widgets/tabs/smart-services/automation_suggestions_model.dart';

/// What the view shows, loaded in one pass.
class AutomationSuggestionsView {
  /// The instance the widget belongs to.
  final SmartServiceInstance instance;

  /// The newest export, null when the instance has produced none yet.
  final ExportSnapshot? snapshot;

  /// Open suggestions: resolved, with at least one target, neither accepted
  /// nor dismissed.
  final List<ResolvedSuggestion> suggestions;

  /// Accepted suggestions, keyed by suggestion id, with the module that carries them.
  final List<AcceptedSuggestion> accepted;

  /// Dismissed suggestions that are resolved and have at least one target, so
  /// they can be restored.
  final List<ResolvedSuggestion> dismissed;

  AutomationSuggestionsView(this.instance, this.snapshot, this.suggestions, this.accepted, this.dismissed);
}

class AcceptedSuggestion {
  final String suggestionId, moduleId;

  /// Null when the suggestion is no longer in the newest export.
  final ResolvedSuggestion? resolved;

  /// The switch-off seconds the module carries, null for none. Only meaningful
  /// when [autoOffKnown].
  final int? autoOffS;

  /// False when the module carries no readable auto-off, for example because it
  /// was accepted before the field existed.
  final bool autoOffKnown;

  AcceptedSuggestion(this.suggestionId, this.moduleId, this.resolved, {this.autoOffS, this.autoOffKnown = false});
}

class AutomationSuggestionsLoader {
  /// Loads the view of the instance [instanceId], the one the widget module
  /// belongs to. Throws when the instance cannot be read.
  static Future<AutomationSuggestionsView> load(String instanceId) async {
    final instance = await SmartServiceService.getInstance(instanceId);

    final exportId = await _exportId(instance.id);
    final snapshot = exportId == null ? null : await _latestSnapshot(exportId);

    final modules = await AutomationEngineService.listModules(
        instanceId: instance.id, moduleType: automationProcessDeploymentModuleType);
    final accepted = acceptedModules(modules);

    final candidates = snapshot?.suggestions ?? const <Suggestion>[];
    final dismissed = <String>{};
    for (final s in candidates) {
      if (accepted.containsKey(s.id)) continue;
      final isDismissedNow = await isDismissed(
        () => ProcessIoService.getVariable(dismissKey(s.id)),
        onError: (e, st) => ErrorReporter.log("Could not read the dismissed state of a suggestion, showing it", e, st),
      );
      if (isDismissedNow) dismissed.add(s.id);
    }

    final resolved = await _resolveAll(candidates);
    final resolvedById = {for (final r in resolved) r.id: r};
    final split = splitSuggestions(
      candidates: candidates,
      accepted: accepted.keys.toSet(),
      dismissed: dismissed,
      resolvedById: resolvedById,
    );

    final modulesById = {for (final m in modules) m.id: m};
    final acceptedEntries = [
      for (final entry in accepted.entries)
        _acceptedEntry(entry.key, entry.value, modulesById[entry.value], resolvedById[entry.key]),
    ];
    return AutomationSuggestionsView(instance, snapshot, split.open, acceptedEntries, split.dismissed);
  }

  static AcceptedSuggestion _acceptedEntry(
      String suggestionId, String moduleId, AutomationModule? module, ResolvedSuggestion? resolved) {
    final ({int? seconds, bool known}) autoOff =
        module == null ? (seconds: null, known: false) : moduleAutoOff(module);
    return AcceptedSuggestion(suggestionId, moduleId, resolved, autoOffS: autoOff.seconds, autoOffKnown: autoOff.known);
  }

  /// The id of the export module of [instanceId], taken from its module data.
  static Future<String?> _exportId(String instanceId) async {
    final modules = await SmartServiceService.getModules(type: automationExportModuleType, instanceId: instanceId);
    for (final m in modules) {
      final data = m.module_data;
      if (data is! Map) continue;
      final export = data["export"];
      if (export is Map && export["ID"] is String) return export["ID"] as String;
    }
    return null;
  }

  /// The newest list of the export. The export holds a row only when its list
  /// changes, so the newest row can be old; last-values returns it regardless.
  static Future<ExportSnapshot?> _latestSnapshot(String exportId) async {
    final dynamic value;
    try {
      value = await DbQueryService.lastValue(exportId, "suggestions");
    } on DioException catch (e) {
      // Before its first row the export has no table, and the wrapper answers
      // 400 "relation ... does not exist": no list yet, not an error.
      if (exportHasNoTable(e.response?.statusCode, e.response?.data)) return null;
      rethrow;
    }
    if (value == null) return null;
    final snapshot = parseExportSuggestions(value);
    if (snapshot.skipped > 0) {
      ErrorReporter.log("Skipped ${snapshot.skipped} unreadable suggestion(s) of the export");
    }
    return snapshot;
  }

  /// Resolves every suggestion against the device types of the devices they
  /// name. Device types and functions are loaded once for all of them.
  static Future<List<ResolvedSuggestion>> _resolveAll(List<Suggestion> suggestions) async {
    if (suggestions.isEmpty) return const [];

    final deviceIds = <String>{};
    for (final s in suggestions) {
      deviceIds.add(s.trigger.deviceId);
      for (final t in s.targets) {
        deviceIds.add(t.deviceId);
      }
    }
    final devices = await DevicesService.getDevicesByIds(deviceIds.toList());
    final names = {for (final d in devices) d.id: d.displayName};

    final typeIds = devices.map((d) => d.device_type_id).toSet();
    final types = <String, DeviceType>{};
    for (final id in typeIds) {
      final type = await DeviceTypesService.getDeviceType(id);
      if (type != null) types[id] = type;
    }
    final typesByDevice = <String, DeviceType>{
      for (final d in devices)
        if (types[d.device_type_id] != null) d.id: types[d.device_type_id]!,
    };

    final functions = {for (final f in await FunctionsService.getFunctions()) f.id: f};

    return [
      for (final s in suggestions)
        resolveSuggestion(s, typesByDevice: typesByDevice, functions: functions, names: names),
    ];
  }
}

/// Whether an answer of the timescale-wrapper says that the export has no table
/// yet, which it has only after its first row.
bool exportHasNoTable(int? status, Object? body) =>
    status == 400 && body != null && body.toString().contains("does not exist");
