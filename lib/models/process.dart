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

/// Parses an ISO timestamp the process engine sends, null when absent or
/// malformed.
DateTime? _time(dynamic v) => v is String ? DateTime.tryParse(v) : null;

String _string(dynamic v) => v is String ? v : "";

/// A process deployment: the definition the engine runs, bound to the cloud
/// or to a gateway by [networkId].
class ProcessDeployment {
  final String id, name, description;

  /// Hub id of the gateway the process runs on; empty for the cloud.
  final String networkId;
  final DateTime? createdAt, updatedAt;

  const ProcessDeployment({
    required this.id,
    required this.name,
    required this.description,
    required this.networkId,
    this.createdAt,
    this.updatedAt,
  });

  factory ProcessDeployment.fromJson(Map<String, dynamic> json) =>
      ProcessDeployment(
        id: _string(json["id"]),
        name: _string(json["name"]),
        description: _string(json["description"]),
        networkId: _string(json["network_id"]),
        createdAt: _time(json["created_at"]),
        updatedAt: _time(json["updated_at"]),
      );
}

/// One run of a deployment.
class ProcessInstance {
  final String id, deploymentId, deploymentName;

  /// Raw engine state: `running`, `completed`, `terminated`, `incident` or
  /// `pending` in automation-engine; any other value is shown as it is.
  final String state;
  final DateTime? createdAt, startedAt, endedAt, lastActivityAt;

  const ProcessInstance({
    required this.id,
    required this.deploymentId,
    required this.deploymentName,
    required this.state,
    this.createdAt,
    this.startedAt,
    this.endedAt,
    this.lastActivityAt,
  });

  bool get isRunning => state == "running";

  /// Whether the debug view has something to say: what a running instance
  /// waits for, or why an instance stopped on an incident.
  bool get hasDebug => isRunning || state == "incident";

  factory ProcessInstance.fromJson(Map<String, dynamic> json) =>
      ProcessInstance(
        id: _string(json["id"]),
        deploymentId: _string(json["deployment_id"]),
        deploymentName: _string(json["deployment_name"]),
        state: _string(json["state"]),
        createdAt: _time(json["created_at"]),
        startedAt: _time(json["started_at"]),
        endedAt: _time(json["ended_at"]),
        lastActivityAt: _time(json["last_activity_at"]),
      );

  /// The last moment anything happened to the instance.
  DateTime? get lastSeen => lastActivityAt ?? endedAt ?? startedAt ?? createdAt;
}

/// The newest instance (by `created_at`) of every deployment, keyed by
/// deployment id. An instance without a creation time loses against one with.
Map<String, ProcessInstance> latestInstancePerDeployment(
    Iterable<ProcessInstance> instances) {
  final latest = <String, ProcessInstance>{};
  for (final instance in instances) {
    final current = latest[instance.deploymentId];
    if (current == null || _isNewer(instance, current)) {
      latest[instance.deploymentId] = instance;
    }
  }
  return latest;
}

bool _isNewer(ProcessInstance a, ProcessInstance b) {
  final at = a.createdAt, bt = b.createdAt;
  if (at == null) return false;
  if (bt == null) return true;
  return at.isAfter(bt);
}

/// A step a token currently sits on.
class ProcessActiveStep {
  final String elementId, elementType, name;
  final DateTime? since;
  final int tokens;

  const ProcessActiveStep({
    required this.elementId,
    required this.elementType,
    required this.name,
    this.since,
    this.tokens = 1,
  });

  factory ProcessActiveStep.fromJson(Map<String, dynamic> json) =>
      ProcessActiveStep(
        elementId: _string(json["element_id"]),
        elementType: _string(json["element_type"]),
        name: _string(json["name"]),
        since: _time(json["since"]),
        tokens: json["tokens"] is int ? json["tokens"] as int : 1,
      );

  String get label => name.isNotEmpty ? name : elementId;
}

/// Something the instance waits for. Only `timer` has been seen; the other
/// kinds carry just [kind] and [elementId].
class ProcessWait {
  final String elementId, kind;
  final DateTime? since;

  /// Timer details, null for a wait that is not a timer.
  final String? timerDefinition;
  final DateTime? dueAt;

  const ProcessWait({
    required this.elementId,
    required this.kind,
    this.since,
    this.timerDefinition,
    this.dueAt,
  });

  bool get isTimer => kind == "timer";

  factory ProcessWait.fromJson(Map<String, dynamic> json) {
    final timer = json["timer"];
    return ProcessWait(
      elementId: _string(json["element_id"]),
      kind: _string(json["kind"]),
      since: _time(json["since"]),
      timerDefinition: timer is Map ? _string(timer["definition"]) : null,
      dueAt: timer is Map ? _time(timer["due_at"]) : null,
    );
  }
}

/// An incident of an instance (automation-engine `model.Incident`: `message`,
/// `element_id`, `element_name`, `time`). The raw map is kept, so a field
/// missing on an older engine falls back instead of failing.
class ProcessIncident {
  final Map<String, dynamic> raw;

  const ProcessIncident(this.raw);

  /// The step the incident happened in: its name, else its id, else empty.
  String get step {
    final name = _string(raw["element_name"]);
    return name.isNotEmpty ? name : _string(raw["element_id"]);
  }

  DateTime? get time => _time(raw["time"]);

  String get message {
    for (final key in const ["error_message", "message", "error"]) {
      final v = raw[key];
      if (v is String && v.isNotEmpty) return v;
    }
    return raw.toString();
  }
}

/// What `GET /instances/{id}/debug` says about a running instance.
class ProcessDebug {
  final List<ProcessActiveStep> active;
  final List<ProcessWait> waits;
  final List<ProcessIncident> incidents;

  const ProcessDebug({
    this.active = const [],
    this.waits = const [],
    this.incidents = const [],
  });

  factory ProcessDebug.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> maps(dynamic v) => v is List
        ? [
            for (final e in v)
              if (e is Map) Map<String, dynamic>.from(e)
          ]
        : const [];
    return ProcessDebug(
      active: maps(json["active"]).map(ProcessActiveStep.fromJson).toList(),
      waits: maps(json["waits"]).map(ProcessWait.fromJson).toList(),
      incidents: maps(json["incidents"]).map(ProcessIncident.new).toList(),
    );
  }

  /// The earliest due time among the timer waits.
  DateTime? nextTimer() {
    DateTime? next;
    for (final w in waits) {
      final due = w.dueAt;
      if (!w.isTimer || due == null) continue;
      if (next == null || due.isBefore(next)) next = due;
    }
    return next;
  }

  /// The name a step shows under: the active step's own name, else its id.
  String stepName(String elementId) {
    for (final a in active) {
      if (a.elementId == elementId && a.name.isNotEmpty) return a.name;
    }
    return elementId;
  }
}
