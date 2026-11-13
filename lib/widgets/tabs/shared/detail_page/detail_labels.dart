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
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/config/functions/function_config.dart';
import 'package:mobile_app/models/aspect.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/widgets/tabs/sensors/sensor_display.dart';
import 'package:mobile_app/widgets/tabs/sensors/switch_tile.dart';

/// Labels and value text of the device detail page's rows. Kept apart from the
/// page so the rules can be tested and the rows built from small pieces.

const _targetAspect = 'target';
const _buttonAspect = 'button';
const _heatingAspect = 'heating';
const _lightingAspect = 'lighting';

/// Carried by almost every variable, so it tells nothing apart.
const _genericAspect = 'device';

/// What a binary-state reading stands for, told by the function and its aspects
/// and not by the device type. The title of each is in [binaryTitles]; this is
/// the one place that maps them.
enum BinaryRole { heatingRunning, heatingEnabled, power, button }

const binaryTitles = {
  BinaryRole.heatingRunning: 'Heating',
  BinaryRole.heatingEnabled: 'Heating enabled',
  BinaryRole.power: 'Power',
  BinaryRole.button: 'Button input',
};

/// The role of [element] when it is an on/off function reading: Button decides
/// first, then Heating (off/heat when its characteristic lists "off" among the
/// values or in its name, else idle/heat), then Lighting, or Device on a
/// reading a Set Device On/Off control switches. Null for anything else. For a
/// group [states] and [isGroup] are those of the group.
BinaryRole? binaryRoleOf(DeviceState element, List<DeviceState> states, {bool isGroup = false}) {
  if (element.isControlling || !isOnOffReading(element.functionId)) return null;
  final names = {for (final id in element.aspectIds) _aspectName(id)};
  if (names.contains(_buttonAspect)) return BinaryRole.button;
  if (names.contains(_heatingAspect)) {
    final c = AppState().characteristics[element.characteristicId];
    final off = c != null && (c.allowed_values?.contains('off') == true || c.name.toLowerCase().contains('off'));
    return off ? BinaryRole.heatingEnabled : BinaryRole.heatingRunning;
  }
  if (names.contains(_lightingAspect)) return BinaryRole.power;
  if (names.contains(_genericAspect) && isSwitchableOnOff(element, states, isGroup: isGroup)) return BinaryRole.power;
  return null;
}

/// The text of a read-only binary reading of [role]: "Heating"/"Idle" for a
/// running state, "On"/"Off" for a heating that is enabled or not, otherwise
/// [readOnlyBinaryText].
String binaryValueText(BinaryRole? role, dynamic value) {
  final flag = heatingFlagOf(value);
  if (flag != null) {
    if (role == BinaryRole.heatingRunning) return flag ? 'Heating' : 'Idle';
    if (role == BinaryRole.heatingEnabled) return flag ? 'On' : 'Off';
  }
  return readOnlyBinaryText(value);
}

/// A heating state as on (true) or off (false): a boolean, or the forms
/// on/off, true/false and heat/idle; null when it is none of them or a group
/// disagrees.
bool? heatingFlagOf(dynamic value) {
  final single = value is List && value.any((v) => v is String) ? commonValue(value) : value;
  if (single is String) {
    return switch (single.toLowerCase()) {
      'on' || 'true' || 'heat' => true,
      'off' || 'false' || 'idle' => false,
      _ => null,
    };
  }
  return switch (onOffReadingOf(single)) {
    OnOffReading.on => true,
    OnOffReading.off => false,
    _ => null,
  };
}

/// What an input with the role Reading does, for a row that offers it.
const readingInputSubtitle = 'Feeds a measured value to the device';

/// [title] continuing a sentence: "Target Temperature" as "target temperature".
/// An abbreviation such as "CO2" keeps its capitals.
String continuedTitle(String title) => title.split(' ').map((word) {
      if (word.isEmpty) return word;
      final second = word.length > 1 ? word[1] : '';
      final abbreviation = second.toUpperCase() == second && second.toLowerCase() != second;
      return abbreviation ? word : word[0].toLowerCase() + word.substring(1);
    }).join(' ');

/// The title of an input with the role Reading whose function measures
/// [quantity]: "External temperature input".
String externalInputTitle(String quantity) =>
    quantity.isEmpty ? 'External input' : 'External ${continuedTitle(quantity)} input';

/// [name] without a leading "Get-" or "Set-": a value is named by what it
/// measures, not by the direction of the platform function.
String stripFunctionPrefix(String name) => name.replaceFirst(RegExp(r'^(Get|Set)-\s*'), '');

/// "occupied_heating_setpoint" as "Occupied heating setpoint"; for a nested
/// variable path the last segment. Empty for a missing path.
String humanizeVariableName(String? path) {
  if (path == null) return '';
  final segment = path.split('.').last.replaceAll('_', ' ').trim();
  if (segment.isEmpty) return '';
  return segment[0].toUpperCase() + segment.substring(1);
}

/// The row's title and the line below it that tells it from the other shown
/// states of the same function.
///
/// Among such states with another aspect set, in this order: a role aspect
/// decides (Target prefixes the title, Button gives the subtitle "Button
/// input"), and a state without it needs nothing against a peer with it; then
/// the aspects other than Device this state has and not all the peers share;
/// then the variable's name. States of one aspect set that differ only by
/// service group are told apart by the group's name.
///
/// An input with the role Reading is titled by [externalInputTitle].
///
/// A binary state with a [BinaryRole] is titled by it, and needs no subtitle
/// unless another row has the same title. [states] are all states of the
/// device or group, to tell what a binary state is switched by; [rows] by
/// default.
({String title, String subtitle}) detailLabel(DeviceState element, List<DeviceState> rows, DeviceInstance? device,
    {List<DeviceState>? states, bool isGroup = false}) {
  var title = stripFunctionPrefix(_functionName(element));
  if (isReadingInput(element)) title = externalInputTitle(title);

  final others = rows.where((s) => s.functionId == element.functionId && s != element).toList();
  final aspectPeers = others.where((s) => s.aspectKey != element.aspectKey).toList();
  final parts = <String>[];

  final all = states ?? rows;
  final role = binaryRoleOf(element, all, isGroup: isGroup);
  var named = false;
  if (role != null) {
    title = binaryTitles[role]!;
    // Only a title of its own is told apart without a subtitle.
    named = !others.any((s) => binaryRoleOf(s, all, isGroup: isGroup) == role && s.aspectKey != element.aspectKey);
  }

  if (aspectPeers.isNotEmpty && !named) {
    final roles = _roles(element);
    var peers = aspectPeers;
    // A peer with a role this state lacks is already told apart by its own
    // title or subtitle.
    for (final role in const [_targetAspect, _buttonAspect]) {
      final has = roles.contains(role);
      if (has && role == _targetAspect) title = 'Target $title';
      if (has && role == _buttonAspect) parts.add('Button input');
      peers = peers.where((s) => _roles(s).contains(role) == has).toList();
    }
    if (peers.isNotEmpty) parts.add(_distinguishing(element, peers));
  }

  final groupKey = element.serviceGroupKey;
  if (device != null && groupKey != null && groupKey != '' && others.any((s) => s.aspectKey == element.aspectKey)) {
    final groups = AppState().deviceTypes[device.device_type_id]?.service_groups;
    parts.add(groups?.firstWhere((g) => g.key == groupKey).name ?? 'MISSING_SERVICE_GROUP_NAME');
  }
  return (title: title, subtitle: parts.where((p) => p.isNotEmpty).join(', '));
}

String _functionName(DeviceState element) {
  final function = AppState().platformFunctions[element.functionId];
  final name = function?.display_name ?? '';
  return name.isNotEmpty ? name : function?.name ?? 'MISSING_FUNCTION_NAME';
}

/// What sets [element] apart from [peers] of another aspect set: its aspects
/// other than Device that not all of them share first (with eight energy values
/// over one aspect and Consumption or Generation and Phase 1 to 3 that names
/// "Consumption, Phase 2"), else its variable's name, else (a group row without
/// a variable path) the full aspect label.
String _distinguishing(DeviceState element, List<DeviceState> peers) {
  final common = element.aspectIds.toSet();
  for (final p in peers) {
    common.retainAll(p.aspectIds);
  }
  final own = element.aspectIds
      .where((id) => !common.contains(id) && !_isRole(id) && _aspectName(id) != _genericAspect)
      .toList();
  if (own.isNotEmpty) {
    return joinAspectNames(AppState().aspects.values, own, missing: 'MISSING_ASPECT_NAME');
  }
  final variable = humanizeVariableName(element.path);
  if (variable.isNotEmpty) return variable;
  return aspectsLabel(element, missing: 'MISSING_ASPECT_NAME', missingClass: 'MISSING_DEVICE_CLASS_NAME');
}

String _aspectName(String id) => joinAspectNames(AppState().aspects.values, [id]).toLowerCase();

/// Whether [s] has the aspect called [name] (lower case).
bool hasAspectNamed(DeviceState s, String name) => s.aspectIds.any((id) => _aspectName(id) == name);

/// The unit a reading of [functionId] is shown in: that of the preferred
/// characteristic, else of the concept's base characteristic.
String readingUnit(String functionId) {
  final preferred = Settings.getFunctionPreferredCharacteristicId(functionId);
  if (preferred != null) return AppState().characteristics[preferred]?.display_unit ?? '';
  return AppState().concepts[AppState().platformFunctions[functionId]?.concept_id]?.getBaseCharacteristic().display_unit ?? '';
}

bool _isRole(String id) {
  final name = _aspectName(id);
  return name == _targetAspect || name == _buttonAspect;
}

Set<String> _roles(DeviceState s) => {
      for (final id in s.aspectIds)
        if (_isRole(id)) _aspectName(id),
    };

/// The text a read-only on/off reading shows instead of a power icon: "On" or
/// "Off", "Mixed" for a group that disagrees, otherwise the value itself with
/// a capital, e.g. "Heat".
String readOnlyBinaryText(dynamic value) {
  switch (onOffReadingOf(value)) {
    case OnOffReading.on:
      return 'On';
    case OnOffReading.off:
      return 'Off';
    case OnOffReading.mixed:
      return 'Mixed';
    case OnOffReading.unknown:
      final text = formatValue(value);
      return text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
  }
}

/// [seconds] as its two largest units: "5 d 3 h", "3 h 12 min", "4 min".
String formatDuration(num seconds) {
  final total = seconds.round();
  final days = total ~/ 86400;
  final hours = total % 86400 ~/ 3600;
  final minutes = total % 3600 ~/ 60;
  if (days > 0) return '$days d $hours h';
  if (hours > 0) return '$hours h $minutes min';
  return '$minutes min';
}

/// A value with its [unit] for a row: a duration of 120 s or more as days,
/// hours and minutes, a number of 1000 or more without decimals; everything
/// else as [formatValue] shows it. A group's list counts as its one value when
/// all members agree.
String formatValueWithUnit(dynamic value, String unit) {
  final single = value is List ? commonValue(value) : value;
  if (single is num) {
    if (unit == 's' && single.abs() >= 120) return formatDuration(single);
    if (unit.isNotEmpty && single.abs() >= 1000) return '${single.round()} $unit';
  }
  return unit.isEmpty ? formatValue(value) : '${formatValue(value)} $unit';
}

/// The label of a sensor card or picker row: [detailLabel], for a control of
/// a "Set-" function with "Set" before the title in sentence case ("Set
/// target temperature"), so its card is not named like its reading's. An
/// input with the role Reading keeps [externalInputTitle]. [siblings] are the
/// states shown for the device or group, [states] all of them.
({String title, String subtitle}) sensorLabel(DeviceState state, List<DeviceState> siblings, DeviceInstance? device,
    {required List<DeviceState> states, bool isGroup = false}) {
  final label = detailLabel(state, siblings, device, states: states, isGroup: isGroup);
  if (!state.isControlling || isReadingInput(state) || !_functionName(state).startsWith('Set-')) return label;
  return (title: 'Set ${continuedTitle(label.title)}', subtitle: label.subtitle);
}

/// [label] on one line, as a card title has no second one.
String joinedLabel(({String title, String subtitle}) label) =>
    label.subtitle.isEmpty ? label.title : '${label.title} · ${label.subtitle}';

/// What a quick toggle of an on/off reading switches, for its icon and tooltip.
enum ToggleKind { power, heating, lighting }

ToggleKind toggleKindOf(DeviceState reading) {
  if (hasAspectNamed(reading, _heatingAspect)) return ToggleKind.heating;
  if (hasAspectNamed(reading, _lightingAspect)) return ToggleKind.lighting;
  return ToggleKind.power;
}

/// The icon of a list row's quick toggle: a flame for heating, a bulb for
/// lighting, otherwise the on/off reading's own power icon. Null while the
/// value is unknown.
Widget? toggleIconOf(DeviceState reading, BuildContext context) {
  final icons = switch (toggleKindOf(reading)) {
    ToggleKind.heating => (on: Icons.local_fire_department, off: Icons.local_fire_department_outlined),
    ToggleKind.lighting => (on: Icons.lightbulb, off: Icons.lightbulb_outline),
    ToggleKind.power => null,
  };
  if (icons != null) {
    switch (onOffReadingOf(reading.value)) {
      case OnOffReading.on:
        return Icon(icons.on);
      case OnOffReading.off:
        return Icon(icons.off);
      case OnOffReading.mixed:
        return const Icon(Icons.remove);
      case OnOffReading.unknown:
        break;
    }
  }
  return functionConfigs[reading.functionId]?.displayValue(reading.value, context);
}

/// The tooltip of a list row's quick toggle: named by what it switches for
/// heating and lighting, otherwise [fallback], the control's own name.
String? toggleTooltipOf(DeviceState reading, String? fallback) => switch (toggleKindOf(reading)) {
      ToggleKind.heating => 'Heating on/off',
      ToggleKind.lighting => 'Light on/off',
      ToggleKind.power => fallback,
    };
