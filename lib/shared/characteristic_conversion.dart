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
import 'package:mobile_app/live/conversion/converter.dart';
import 'package:mobile_app/models/characteristic.dart';
import 'package:mobile_app/services/settings.dart';

/// Which characteristic a value of a function is in, and conversion between
/// two of them with the in-app converter and the formulas of the concepts.

final _converter = LocalConverter();

/// The base characteristic id of [functionId]'s concept, null when the
/// function or concept is unknown or names none.
String? baseCharacteristicIdOf(String functionId) {
  final id = AppState().concepts[AppState().platformFunctions[functionId]?.concept_id]?.base_characteristic_id;
  return id == null || id.isEmpty ? null : id;
}

/// The characteristic id readings of [functionId] are in: the preferred one,
/// else the concept's base, which is what a command without a characteristic
/// is answered in.
String? readingCharacteristicId(String functionId) =>
    Settings.getFunctionPreferredCharacteristicId(functionId) ?? baseCharacteristicIdOf(functionId);

/// The characteristic [readingCharacteristicId] names, looked up among all
/// characteristics and those of the function's concept.
Characteristic? readingCharacteristic(String functionId) {
  final id = readingCharacteristicId(functionId);
  if (id == null) return null;
  final known = AppState().characteristics[id];
  if (known != null) return known;
  final concept = AppState().concepts[AppState().platformFunctions[functionId]?.concept_id];
  return concept?.characteristics.where((c) => c.id == id).firstOrNull;
}

/// [value] converted from characteristic [from] to [to] over the built-in
/// casts and the formulas of [conceptIds]; null (not wrapped) when there is no
/// path, a cast fails, or a number comes out NaN or infinite.
({dynamic value})? convertCharacteristic(dynamic value, String from, String to, {Iterable<String?> conceptIds = const []}) {
  if (from == to) return (value: value);
  final extensions = <ConversionEdge>[];
  for (final id in {...conceptIds}) {
    for (final c in AppState().concepts[id]?.conversions ?? const []) {
      extensions.add(ConversionEdge(
          from: c.from, to: c.to, distance: c.distance, formula: c.formula, placeholderName: c.placeholder_name));
    }
  }
  try {
    final out = _converter.convert(value, from, to, extensions: extensions);
    if (out is num && !out.isFinite) return null;
    return (value: out);
  } on ConversionException {
    return null;
  }
}
