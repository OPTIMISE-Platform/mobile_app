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

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/config/functions/function_config.dart';
import 'package:mobile_app/models/characteristic.dart';
import 'package:mobile_app/models/content_variable.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/widgets/tabs/sensors/switch_tile.dart';
import 'package:mobile_app/widgets/tabs/shared/device_state_action.dart';

// What the Android device controls offer for a device or group: the entries
// the platform side lists and the lookups from such an entry back to the
// states it stands for. No I/O, so a test can run it on states built by hand.

/// A control either switches on and off or sets a number within a range.
enum ControlKind { toggle, range }

/// The slider of a [ControlKind.range] control.
class ControlRange {
  final double min, max, step;

  /// The unit the characteristic displays; null when it has none.
  final String? unit;
  final bool integer;

  const ControlRange(this.min, this.max, this.step, this.unit, this.integer);
}

/// An entry of the controls list: a reading together with how it is controlled.
class ControlEntry {
  /// The reading the control shows the value of.
  final DeviceState state;
  final ControlKind kind;

  /// Set for [ControlKind.range].
  final ControlRange? range;

  const ControlEntry(this.state, this.kind, [this.range]);
}

/// The fields of an entry that are no part of the control id the platform side
/// keeps (`DeviceState.getId()` in Kotlin removes them). Keeping this list
/// and the Kotlin one equal is what keeps the ids of existing controls stable.
const controlExtraFields = ['kind', 'min', 'max', 'step', 'unit', 'integer'];

String? get _onOff => dotenv.env['FUNCTION_GET_ON_OFF_STATE'];

/// The device class of thermostats, whose set-temperature control gets the
/// range of [_thermostatSetpoints].
const thermostatDeviceClass = 'urn:infai:ses:device-class:997937d6-c5f3-4486-b67c-114675038393';

/// The aspect Target, that of a thermostat's setpoint.
const targetAspect = 'urn:infai:ses:aspect:4f4188b6-f944-45fa-9429-15655f691397';

/// The setpoints a radiator thermostat accepts, per temperature characteristic.
/// The platform leaves temperature open at the top (Degree Celsius has no
/// maximum), so without these a thermostat would get no slider. Only for
/// thermostats: a boiler sets its water temperature through the same function
/// and characteristic, far above 30 °C.
const _thermostatSetpoints = <String, (double, double)>{
  'urn:infai:ses:characteristic:5ba31623-0ccb-4488-bfb7-f73b50e03b5a': (5, 30), // Degree Celsius
  'urn:infai:ses:characteristic:a49a48fc-3a2c-4149-ac7f-1a5482d4c6e1': (5, 30), // Degree Celsius (int)
  'urn:infai:ses:characteristic:75b2d113-1d03-4ef8-977a-8dbcbb31a683': (278.15, 303.15), // Kelvin
};

/// The setpoint range of a thermostat for a temperature characteristic, null
/// for one the table does not list.
(double, double)? thermostatSetpointRange(String characteristicId) => _thermostatSetpoints[characteristicId];

/// Whether [device] is a thermostat, by the class of its device type.
bool deviceIsThermostat(DeviceInstance device) =>
    AppState().deviceTypes[device.device_type_id]?.device_class_id == thermostatDeviceClass;

/// Whether all devices of [group] are thermostats: its criteria name device
/// classes, and only that of thermostats.
bool groupIsThermostats(DeviceGroup group) {
  final classes = {
    for (final c in group.criteria ?? const <DeviceGroupCriteria>[])
      if (c.device_class_id.isNotEmpty) c.device_class_id,
  };
  return classes.length == 1 && classes.single == thermostatDeviceClass;
}

/// The entries a device with [states] offers: its on/off readings that a
/// control switches, then the readings that exactly one control with a
/// numeric range sets. [thermostat] as for [controlRange].
List<ControlEntry> deviceControlEntries(List<DeviceState> states, {bool thermostat = false}) {
  final entries = <ControlEntry>[
    for (final s in states)
      if (s.functionId == _onOff && isSwitchableOnOff(s, states)) ControlEntry(s, ControlKind.toggle),
  ];
  final ranges = <String, ControlRange?>{};
  for (final s in states) {
    if (s.isControlling || s.functionId == _onOff) continue;
    final control = controlOfReading(s, states, isGroup: false);
    if (control == null) continue;
    final range =
        ranges.putIfAbsent("${control.functionId}|${control.aspectKey}", () => controlRange(control, thermostat: thermostat));
    if (range != null) entries.add(ControlEntry(s, ControlKind.range, range));
  }
  return entries;
}

/// The entries a group offers, among its [shown] states ([DeviceGroup.shownStates])
/// with the controls looked up in [all] its states. A group switches only when
/// there is one control for on and one for off. [thermostat] as for
/// [controlRange].
List<ControlEntry> groupControlEntries(List<DeviceState> shown, List<DeviceState> all, {bool thermostat = false}) {
  final entries = <ControlEntry>[];
  final ranges = <String, ControlRange?>{};
  for (final s in shown) {
    if (s.isControlling) continue;
    if (s.functionId == _onOff) {
      if (isSwitchableOnOff(s, all, isGroup: true) &&
          resolveGroupControl(s, all, dotenv.env['FUNCTION_SET_ON_STATE']) != null &&
          resolveGroupControl(s, all, dotenv.env['FUNCTION_SET_OFF_STATE']) != null) {
        entries.add(ControlEntry(s, ControlKind.toggle));
      }
      continue;
    }
    final control = controlOfReading(s, all, isGroup: true);
    if (control == null) continue;
    final range =
        ranges.putIfAbsent("${control.functionId}|${control.aspectKey}", () => controlRange(control, thermostat: thermostat));
    if (range != null) entries.add(ControlEntry(s, ControlKind.range, range));
  }
  return entries;
}

/// The one control of [states] that acts on [reading] by setting a value, null
/// when there is none or more than one. Paired by service group and aspects
/// through the function configs, as the detail page does. A group whose
/// reading pairs with none this way has the control of the concept's single
/// controlling function ([resolveGroupControl]); a group of thermostats has a
/// set-temperature control per aspect and is paired by aspect.
DeviceState? controlOfReading(DeviceState reading, List<DeviceState> states, {required bool isGroup}) {
  final controls = [
    for (final f in relatedControllingFunctionsOf(reading.functionId) ?? const <String>[])
      ...reading.controlsFor(states, f),
  ];
  if (controls.length == 1) return controls.single;
  return isGroup && controls.isEmpty ? resolveGroupControl(reading, states) : null;
}

/// The slider the characteristic of [control]'s function allows, null when it
/// is no number with a minimum and a maximum. The platform side builds a
/// range template from it, which refuses a value outside the range and a step
/// of zero, so what does not fit is left out here.
///
/// For a [thermostat] (a device, or a group of only such devices) the
/// setpoint, the control of the aspect Target, takes the range of
/// [_thermostatSetpoints] when its temperature characteristic has no maximum.
/// A thermostat's other temperature controls, such as the external input
/// that stands in for its own sensor, stay without a slider.
ControlRange? controlRange(DeviceState control, {bool thermostat = false}) {
  final controlFunctionId = control.functionId;
  final setpoint = thermostat && control.aspectId == targetAspect;
  final Characteristic? characteristic;
  try {
    characteristic = (functionConfigs[controlFunctionId] ?? FunctionConfigDefault(controlFunctionId)).characteristic;
  } catch (_) {
    // A config without a base characteristic of its concept.
    return null;
  }
  if (characteristic == null) return null;
  final integer = characteristic.type == ContentVariable.integer;
  if (!integer && characteristic.type != ContentVariable.float) return null;
  var min = characteristic.min_value;
  var max = characteristic.max_value;
  final setpoints = setpoint && (max == null || !max.isFinite) ? _thermostatSetpoints[characteristic.id] : null;
  if (setpoints != null) (min, max) = setpoints;
  if (min == null || max == null || !min.isFinite || !max.isFinite || max <= min) return null;
  final unit = characteristic.display_unit;
  return ControlRange(min, max, integer ? 1 : 0.5, unit.isEmpty ? null : unit, integer);
}

/// The reading an entry from the platform side means among [states]: the
/// non-controlling states of its function at its place, a service and path for
/// a device and a device class for a group. [entryAspectIds] and the entry's
/// aspect settle which of several; null when there is none or it stays open.
DeviceState? readingForEntry(DeviceState entry, List<String>? entryAspectIds, List<DeviceState> states,
    {required bool isGroup}) {
  final samePlace = states
      .where((s) =>
          !s.isControlling &&
          s.functionId == entry.functionId &&
          (isGroup
              ? (s.deviceClassId ?? '') == (entry.deviceClassId ?? '')
              : s.serviceGroupKey == entry.serviceGroupKey && s.serviceId == entry.serviceId && s.path == entry.path))
      .toList(growable: false);
  return switch (samePlace.length) {
    0 => null,
    1 => samePlace.single,
    _ => DeviceState.resolveAspects(samePlace, entry.aspectId, entryAspectIds),
  };
}

/// The value an entry shows, as the platform side takes it: a boolean for a
/// toggle, a number for a range and null while nothing is known. A group's
/// list of member values counts as on when all members that answered are, as
/// the group's list row has it; the members of a range must agree.
dynamic controlValue(ControlKind kind, dynamic raw, {required bool isGroup}) {
  if (kind == ControlKind.toggle) {
    return switch (onOffReadingOf(raw)) {
      OnOffReading.on => true,
      OnOffReading.off || OnOffReading.mixed => false,
      OnOffReading.unknown => null,
    };
  }
  dynamic value = raw;
  if (raw is List) {
    value = isGroup ? commonValue(raw) : (raw.length == 1 ? raw.single : null);
  }
  return value is num ? value.toDouble() : null;
}

/// [entry] as the platform side takes it: the fields of [DeviceState.toJson]
/// that make up the control id, unchanged, plus the kind and, for a range, its
/// slider. [value] is the current value, already through [controlValue].
Map<String, dynamic> controlEntryJson(ControlEntry entry, dynamic value) {
  final json = entry.state.toJson()
    // Whole devices and groups, which the platform side does not read.
    ..remove('deviceInstance')
    ..remove('deviceGroup');
  return withControlFields(json, entry.kind, entry.range, value);
}

/// A copy of [base], the fields of an entry the platform side sent, with the
/// [kind], the slider of [range] and [value] set. Everything else is kept as
/// it came, so the control id of the answer is that of the request.
Map<String, dynamic> withControlFields(Map<String, dynamic> base, ControlKind kind, ControlRange? range, dynamic value) {
  final json = {...base}..removeWhere((key, _) => controlExtraFields.contains(key));
  json['value'] = value;
  json['kind'] = kind.name;
  if (range != null) {
    json['min'] = range.min;
    json['max'] = range.max;
    json['step'] = range.step;
    if (range.unit != null) json['unit'] = range.unit;
    json['integer'] = range.integer;
  }
  return json;
}
