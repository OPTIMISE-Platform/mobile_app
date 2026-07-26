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

import 'package:mobile_app/models/sensor_pin.dart';

/// One user-defined tab on the sensors page, holding its own set of pinned
/// sensor values.
///
/// Persisted as JSON via `Settings.getSensorTabs`/`setSensorTabs`.
class SensorTab {
  /// Stable identity, so renaming or reordering never moves values between tabs.
  final String id;
  final String name;

  /// Material icon name (a key of `iconNameToCodePoints`), optional.
  final String? iconName;

  final List<SensorPin> pins;

  const SensorTab({
    required this.id,
    required this.name,
    this.iconName,
    this.pins = const [],
  });

  /// Creates a tab with a fresh id.
  factory SensorTab.create({required String name, String? iconName}) =>
      SensorTab(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        iconName: iconName,
      );

  factory SensorTab.fromJson(Map<String, dynamic> json) => SensorTab(
    id: json['id'] as String,
    name: json['name'] as String,
    iconName: json['iconName'] as String?,
    pins: ((json['pins'] as List<dynamic>?) ?? const [])
        .map((e) => SensorPin.fromJson(e as Map<String, dynamic>))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'iconName': iconName,
    'pins': pins,
  };

  SensorTab copyWith({String? name, String? iconName, List<SensorPin>? pins}) {
    final newIconName = iconName ?? this.iconName;
    return SensorTab(
      id: id,
      name: name ?? this.name,
      // An empty string clears the icon.
      iconName: (newIconName == null || newIconName.isEmpty)
          ? null
          : newIconName,
      pins: pins ?? this.pins,
    );
  }
}
