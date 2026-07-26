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

import 'package:mobile_app/models/device_state.dart';

/// A single sensor value the user pinned to the sensors page.
///
/// Identifies one [DeviceState] of one device — a reading or a control. The
/// tuple mirrors how [StateHelper] itself de-duplicates states (service group +
/// function + aspect, per controlling direction), so it stays stable across
/// reloads even though `DeviceState` objects are rebuilt on every device load.
///
/// Persisted as part of a [SensorTab] via `Settings.getSensorTabs`.
class SensorPin {
  final String deviceId;
  final String functionId;
  final String? aspectId;
  final String? serviceGroupKey;

  /// Whether this refers to a controlling state (a switch/input) rather than a
  /// readable measurement. Part of the identity because a device can have both
  /// for the same function and aspect.
  final bool isControlling;

  /// User-chosen label shown instead of the function name.
  final String? alias;

  /// Material icon name (a key of `iconNameToCodePoints`), shown on the card.
  final String? iconName;

  const SensorPin({
    required this.deviceId,
    required this.functionId,
    this.aspectId,
    this.serviceGroupKey,
    this.isControlling = false,
    this.alias,
    this.iconName,
  });

  /// Describes [state] so it can be found again after a reload.
  factory SensorPin.of(DeviceState state) => SensorPin(
    deviceId: state.deviceId ?? '',
    functionId: state.functionId,
    aspectId: state.aspectId,
    serviceGroupKey: state.serviceGroupKey,
    isControlling: state.isControlling,
  );

  factory SensorPin.fromJson(Map<String, dynamic> json) => SensorPin(
    deviceId: json['deviceId'] as String,
    functionId: json['functionId'] as String,
    aspectId: json['aspectId'] as String?,
    serviceGroupKey: json['serviceGroupKey'] as String?,
    // Absent in entries written before controlling states could be pinned.
    isControlling: json['isControlling'] as bool? ?? false,
    alias: json['alias'] as String?,
    iconName: json['iconName'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'functionId': functionId,
    'aspectId': aspectId,
    'serviceGroupKey': serviceGroupKey,
    'isControlling': isControlling,
    'alias': alias,
    'iconName': iconName,
  };

  /// Returns a copy with the presentation fields replaced. Pass an empty string
  /// to clear [alias] / [iconName].
  SensorPin copyWith({String? alias, String? iconName}) {
    final newAlias = alias ?? this.alias;
    final newIconName = iconName ?? this.iconName;
    return SensorPin(
      deviceId: deviceId,
      functionId: functionId,
      aspectId: aspectId,
      serviceGroupKey: serviceGroupKey,
      isControlling: isControlling,
      alias: (newAlias == null || newAlias.isEmpty) ? null : newAlias,
      iconName: (newIconName == null || newIconName.isEmpty)
          ? null
          : newIconName,
    );
  }

  /// Whether [state] is the state this pin refers to.
  bool matches(DeviceState state) =>
      state.isControlling == isControlling &&
      state.deviceId == deviceId &&
      state.functionId == functionId &&
      state.aspectId == aspectId &&
      state.serviceGroupKey == serviceGroupKey;

  /// Equality covers only which sensor is referenced, deliberately excluding
  /// [alias] and [iconName]: it backs "is this value already on the page?" and
  /// removal, both of which must not be affected by relabelling.
  @override
  bool operator ==(Object other) =>
      other is SensorPin &&
      other.deviceId == deviceId &&
      other.functionId == functionId &&
      other.aspectId == aspectId &&
      other.serviceGroupKey == serviceGroupKey &&
      other.isControlling == isControlling;

  @override
  int get hashCode => Object.hash(
    deviceId,
    functionId,
    aspectId,
    serviceGroupKey,
    isControlling,
  );
}
