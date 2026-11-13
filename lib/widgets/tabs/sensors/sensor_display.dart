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

import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/aspect.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/services/settings.dart';

/// Naming and unit resolution for a single [DeviceState], shared by the sensors
/// page and its picker so both label a value identically.
///
/// Mirrors the logic the device detail page uses for its function rows (which
/// keeps it private); kept here as small standalone helpers rather than
/// refactoring that page.

/// The function's human-readable name, e.g. "Temperature".
String sensorTitle(DeviceState state) {
  final function = AppState().platformFunctions[state.functionId];
  final displayName = function?.display_name;
  if (displayName != null && displayName.isNotEmpty) return displayName;
  return function?.name ?? 'MISSING_FUNCTION_NAME';
}

/// The aspect names of [state]; for one without aspects, the name of the
/// device class a group criterion names, as a group lists a control by both.
/// An unknown or absent aspect contributes [missing], an unknown class
/// [missingClass], or nothing when that is null.
String aspectsLabel(DeviceState state, {String? missing, String? missingClass}) {
  if (state.aspectIds.isNotEmpty) {
    return joinAspectNames(AppState().aspects.values, state.aspectIds, missing: missing);
  }
  final classId = state.deviceClassId;
  if (classId == null || classId.isEmpty) return missing ?? '';
  return AppState().deviceClasses[classId]?.name ?? missingClass ?? '';
}

/// The display unit for [state], or an empty string when it has none.
String sensorUnit(DeviceState state) {
  final preferred = Settings.getFunctionPreferredCharacteristicId(
    state.functionId,
  );
  if (preferred != null) {
    return AppState().characteristics[preferred]?.display_unit ?? '';
  }
  final conceptId = AppState().platformFunctions[state.functionId]?.concept_id;
  return AppState().concepts[conceptId]?.getBaseCharacteristic().display_unit ??
      '';
}
