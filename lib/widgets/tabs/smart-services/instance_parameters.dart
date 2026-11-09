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

// The parameter list of an instance as the edit flow and the heating widget
// send it: the release's parameters with the values the instance has now.

import 'package:mobile_app/models/smart_service.dart';
import 'package:mobile_app/services/smart_service.dart';
import 'package:mobile_app/widgets/tabs/smart-services/heating_schedule_model.dart';

/// Loads the parameters of the release of [instance] and copies `value` and
/// `value_label` from the instance by id. The repository replaces the whole
/// list on a write, so every parameter must go out with its current value.
Future<List<SmartServiceExtendedParameter>> loadInstanceParameters(SmartServiceInstance instance) async {
  final parameters = await SmartServiceService.getReleaseParameters(instance.release_id);
  copyInstanceValues(parameters, instance);
  return parameters;
}

void copyInstanceValues(List<SmartServiceExtendedParameter> parameters, SmartServiceInstance instance) {
  for (final p in parameters) {
    final existing = instance.parameters!.firstWhere((e) => p.id == e.id);
    p.value = existing.value;
    p.value_label = existing.value_label;
  }
}

/// Re-reads the instance first, because the PUT replaces every parameter; no release id, since the
/// release parameters always describe the current version.
Future<void> saveHeatingPlan(SmartServiceInstance instance, HeatingPlan plan) async {
  final current = await SmartServiceService.getInstance(instance.id);
  final parameters = await loadInstanceParameters(current);
  // The thermostats may have changed since the plan was edited; a plan that no longer fits must not be sent.
  final problem = plan.problem(parseHeatingThermostats(parameters.firstWhere((p) => p.id == "thermostats").value));
  if (problem != null) throw HeatingScheduleException("The plan no longer fits the thermostats. $problem");
  parameters.firstWhere((p) => p.id == "schedule").value = plan.serialise();
  parameters.firstWhere((p) => p.id == "setback").value = plan.setback.round();
  await SmartServiceService.updateInstanceParameters(current.id, parameters.map((e) => e.toSmartServiceParameter()).toList());
}
