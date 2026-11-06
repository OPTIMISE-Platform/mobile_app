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
import 'package:mobile_app/models/process.dart';
import 'package:mobile_app/theme.dart';

/// What the list and the detail page know about one deployment: the
/// deployment, its newest instance and, for a running one, the debug data once
/// it has arrived.
class ProcessEntry {
  final ProcessDeployment deployment;
  final ProcessInstance? instance;
  final ProcessDebug? debug;

  const ProcessEntry(this.deployment, this.instance, this.debug);

  ProcessEntry withDebug(ProcessDebug? debug) =>
      ProcessEntry(deployment, instance, debug);

  bool get hasIncident => debug != null && debug!.incidents.isNotEmpty;
}

/// The state chip of a process: its label and the colour it is drawn in.
({String label, Color color}) processStatus(
    BuildContext context, ProcessEntry entry) {
  final scheme = Theme.of(context).colorScheme;
  final instance = entry.instance;
  if (instance == null) {
    return (label: "Not running", color: scheme.onSurfaceVariant);
  }
  if (entry.hasIncident || instance.state == "incident") {
    return (label: "Incident", color: context.appColors.error);
  }
  return switch (instance.state) {
    "running" => (label: "Running", color: context.appColors.appInk),
    "completed" => (label: "Completed", color: scheme.onSurfaceVariant),
    "terminated" => (label: "Stopped", color: scheme.onSurfaceVariant),
    "pending" => (label: "Pending", color: scheme.onSurfaceVariant),
    final other => (label: other, color: scheme.onSurfaceVariant),
  };
}

/// Outlined label in the style of the device list's status chip.
class ProcessStatusChip extends StatelessWidget {
  const ProcessStatusChip(this.entry, {super.key});

  final ProcessEntry entry;

  @override
  Widget build(BuildContext context) {
    final status = processStatus(context, entry);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xs, vertical: 1),
      decoration: BoxDecoration(
          border: Border.all(color: status.color),
          borderRadius: BorderRadius.circular(8)),
      child: Text(status.label,
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(color: status.color)),
    );
  }
}
