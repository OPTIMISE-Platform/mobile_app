/*
 * Copyright 2022 InfAI (CC SES)
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

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show mergeSort;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:isar_community/isar.dart';
import 'package:mobile_app/config/functions/function_config.dart';
import 'package:mobile_app/models/device_command.dart';
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/services/device_commands.dart';
import 'package:mobile_app/shared/device_controls.dart';
import 'package:mobile_app/shared/error_reporter.dart';
import 'package:mobile_app/shared/isar.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/detail_page.dart';
import 'package:mobile_app/widgets/tabs/shared/device_state_action.dart';

import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_state.dart';

import 'navigator_key.dart';

/// The device and group a control id points at, with their states prepared
/// and bound to them: a command built from these states reaches the gateway
/// of the network.
class _Target {
  final DeviceInstance? device;
  final DeviceGroup? group;

  _Target(this.device, this.group);

  bool get isGroup => group != null;
  List<DeviceState> get states => device?.states ?? group!.states;

  /// Whether it stands for thermostats only, which widens a setpoint's range
  /// ([controlRange]).
  bool get thermostat => device != null ? deviceIsThermostat(device!) : groupIsThermostats(group!);
}

/// The channel the Android device controls talk through. Control ids are the
/// fields of a [DeviceState] as the platform side keeps them (`DeviceState.kt`
/// reduces them to the id and back), so the states a command acts on are
/// looked up again from the cache by those fields rather than taken from the
/// request: only the states of a device or group in the cache carry the
/// binding that routes a command through the gateway.
class NativePipe {
  static const MethodChannel controlMethodChannel =
      MethodChannel("flutter/controlMethodChannel");

  /// Settles what must be loaded before a call is answered, for the engine
  /// that runs without the app (`controlsMain`). Null in the app's own.
  static Future<void> Function()? _prepare;
  static Future<void>? _ready;

  /// The device readings the platform side shows controls for, from its
  /// requests for control values in this process. Only these get a changed
  /// value passed on; the platform side asks for every control it shows.
  static final Set<String> _watched = {};

  @visibleForTesting
  static void resetWatchedForTest() => _watched.clear();

  static String _watchKey(String? deviceId, String? serviceId, String? functionId, String? aspectId) =>
      [deviceId ?? '', serviceId ?? '', functionId ?? '', aspectId ?? ''].join('|');

  /// Any age: what the cache holds is served, a fetch only fills a gap.
  static const _anyAge = Duration(days: 36500);

  /// [prepare] runs on the first call and again on the next one if it failed;
  /// the handler is set at once so that calls arriving while it runs wait for
  /// it instead of finding no handler.
  static void init({Future<void> Function()? prepare}) {
    if (prepare != null) _prepare = prepare;
    controlMethodChannel.setMethodCallHandler((call) async {
      await _awaitReady();
      switch (call.method) {
        case "getToggleStateless":
          return json.encode(await _listControls());
        case "setToggle":
          return await _setToggle(_entryArguments(call.arguments));
        case "setValue":
          return await _setValue(_entryArguments(call.arguments));
        case "getToggleStates":
          return await _readStates(json.decode(call.arguments) as List<dynamic>);
        case "openDetailPage":
          await _openDetailPage(call.arguments);
          return null;
        default:
          throw MissingPluginException("not implemented");
      }
    });
    if (prepare != null) {
      // Started now rather than by the first call, which may come late.
      unawaited(_awaitReady().catchError((Object e, StackTrace s) =>
          ErrorReporter.log("Could not prepare the device controls", e, s)));
    }
  }

  static Future<void> _awaitReady() {
    final prepare = _prepare;
    if (prepare == null) return Future.value();
    return _ready ??= prepare().catchError((Object e, StackTrace s) {
      // The next call tries again; a failed start must not stay for good in
      // an engine the system keeps.
      _ready = null;
      Error.throwWithStackTrace(e, s);
    });
  }

  /// Loads what a call needs, ahead of the first one: the metadata and the
  /// networks with their gateways, both from the cache.
  static Future<void> loadForControls() async {
    await _ensureMetadata();
    await _ensureNetworks();
  }

  static Map<String, dynamic> _entryArguments(dynamic arguments) =>
      json.decode(arguments as String) as Map<String, dynamic>;

  static Isar _db() {
    final db = isar;
    if (db == null) throw "The cache is not open";
    return db;
  }

  /// The metadata the states are made of, from the cache. A fetch happens only
  /// for what the cache does not hold, and the function configs are built again
  /// after it, since one built before has no characteristic.
  static Future<void> _ensureMetadata() async {
    final state = AppState();
    final loads = [
      if (state.platformFunctions.isEmpty) state.loadNestedFunctions(maxAge: _anyAge, quiet: true),
      if (state.concepts.isEmpty) state.loadConcepts(maxAge: _anyAge, quiet: true),
      if (state.characteristics.isEmpty) state.loadCharacteristics(maxAge: _anyAge, quiet: true),
      if (state.aspects.isEmpty) state.loadAspects(maxAge: _anyAge, quiet: true),
    ];
    if (loads.isNotEmpty) {
      await Future.wait(loads);
      reinit();
    }
    if (state.platformFunctions.isEmpty) throw "The functions are not available";
  }

  /// The networks, which a group takes its gateway from when it is read from
  /// the cache, and the gateways attached to them.
  // A reload running in the app's engine empties the networks and assigns
  // their gateways only at its end, so a command in between would miss them.
  static Future<void> _ensureNetworks() async {
    await AppState().networksSettled();
    if (AppState().networks.isEmpty) await AppState().loadNetworks();
  }

  static Future<void> _ensureTypes(Iterable<String> typeIds) async {
    await AppState().loadStoredDeviceTypes();
    await AppState().ensureDeviceTypes(typeIds);
  }

  static Future<_Target> _deviceTarget(String id) async {
    await _ensureMetadata();
    await _ensureNetworks();
    final device = await _db().deviceInstances.where().idEqualTo(id).findFirst();
    if (device == null) throw "Device $id not found";
    await _ensureTypes([device.device_type_id]);
    final deviceType = AppState().deviceTypes[device.device_type_id];
    if (deviceType == null) {
      throw "Device type ${device.device_type_id} not available";
    }
    device.prepareStates(deviceType);
    return _Target(device, null);
  }

  static Future<_Target> _groupTarget(String id) async {
    await _ensureMetadata();
    await _ensureNetworks();
    final group = await _db().deviceGroups.where().idEqualTo(id).findFirst();
    if (group == null) throw "Group $id not found";
    group.prepareStates();
    return _Target(null, group);
  }

  /// The device or group of an entry's id fields, looked up once per call in
  /// [cache].
  static Future<_Target> _targetOf(Map<String, dynamic> raw, Map<String, _Target> cache) async {
    final groupId = raw['groupId'] as String?;
    final deviceId = raw['deviceId'] as String?;
    if (deviceId != null) {
      return cache["device:$deviceId"] ??= await _deviceTarget(deviceId);
    }
    if (groupId != null) {
      return cache["group:$groupId"] ??= await _groupTarget(groupId);
    }
    throw "The control names neither a device nor a group";
  }

  /// All controls offered: devices' and groups' on/off readings that a control
  /// switches and the readings set through a numeric range. Sorted by the name
  /// the control shows: Android lists them in the order given.
  static Future<List<Map<String, dynamic>>> _listControls() async {
    await _ensureMetadata();
    await _ensureNetworks();
    final db = _db();
    final devices = await db.deviceInstances.where().findAll();
    await _ensureTypes(devices.map((d) => d.device_type_id));
    final deviceTypes = AppState().deviceTypes;
    final controls = <Map<String, dynamic>>[];
    for (final device in devices) {
      final type = deviceTypes[device.device_type_id];
      if (type == null) continue;
      device.prepareStates(type);
      for (final entry in deviceControlEntries(device.states, thermostat: deviceIsThermostat(device))) {
        controls.add(controlEntryJson(entry, null));
      }
    }
    for (final group in await db.deviceGroups.where().findAll()) {
      group.prepareStates();
      for (final entry in groupControlEntries(group.shownStates, group.states, thermostat: groupIsThermostats(group))) {
        controls.add(controlEntryJson(entry, null));
      }
    }
    String key(Map<String, dynamic> c, String field) => (c[field] as String? ?? '').toLowerCase();
    // Stable, so a device's toggle stays before its sliders.
    mergeSort(controls, compare: (a, b) {
      final byName = key(a, 'name').compareTo(key(b, 'name'));
      return byName != 0 ? byName : key(a, 'serviceGroupName').compareTo(key(b, 'serviceGroupName'));
    });
    return controls;
  }

  static List<String>? _aspectIdsOf(Map<String, dynamic> raw) => (raw['aspectIds'] as List<dynamic>?)?.cast<String>();

  /// Switches an on/off control. The control that acts on the reading is looked
  /// up in the device's or group's states, so the command carries its binding.
  /// The answer holds the command's responses and the entry as it now is: the
  /// new state, taken as given since no reading has caught up yet.
  static Future<String> _setToggle(Map<String, dynamic> raw) async {
    final newState = raw['value'];
    if (newState is! bool) throw "A toggle needs a boolean";
    final entry = DeviceState.fromJson(raw);
    final target = await _targetOf(raw, {});
    final controllingFunction = functionConfigs[dotenv.env['FUNCTION_GET_ON_OFF_STATE']]?.getRelatedControllingFunction(!newState);
    if (controllingFunction == null) throw "Found no controlling function, check device type!";
    final List<DeviceState> controllingStates;
    if (target.isGroup) {
      final control = resolveGroupControl(
          readingForEntry(entry, _aspectIdsOf(raw), target.states, isGroup: true) ?? entry, target.states, controllingFunction);
      controllingStates = control == null ? const [] : [control];
    } else {
      controllingStates = controlsForToggle(entry, _aspectIdsOf(raw), target.states, controllingFunction);
    }
    if (controllingStates.isEmpty) {
      throw "Found no controlling service, check device type!";
    }
    if (controllingStates.length > 1) {
      throw "Found more than one controlling service, check device type!";
    }
    final responses = await DeviceCommandsService.runCommands([controllingStates[0].toCommand()]);
    return json.encode({
      'responses': responses,
      'state': withControlFields(raw, ControlKind.toggle, null, newState),
    });
  }

  /// Sets the value of a range control: the control is the one the reading is
  /// paired with, the input the value held to the characteristic's range. The
  /// answer holds the responses and the entry with the value read back, or the
  /// one set when the reading fails.
  static Future<String> _setValue(Map<String, dynamic> raw) async {
    final requested = raw['value'];
    if (requested is! num) throw "A value control needs a number";
    final entry = DeviceState.fromJson(raw);
    final target = await _targetOf(raw, {});
    final reading = readingForEntry(entry, _aspectIdsOf(raw), target.states, isGroup: target.isGroup);
    if (reading == null) throw "Found no reading for the control, check device type!";
    final control = controlOfReading(reading, target.states, isGroup: target.isGroup);
    if (control == null) throw "Found no single controlling service, check device type!";
    final range = controlRange(control, thermostat: target.thermostat);
    if (range == null) throw "The control has no value range";
    final clamped = requested.toDouble().clamp(range.min, range.max);
    final dynamic input = range.integer ? clamped.round() : clamped;
    final responses = await DeviceCommandsService.runCommands([control.toCommand(input)]);
    dynamic value = clamped;
    if (responses.length == 1 && responses.single.status_code == 200) {
      value = await _readValue(reading, ControlKind.range, target.isGroup) ?? value;
    }
    return json.encode({
      'responses': responses,
      'state': withControlFields(raw, ControlKind.range, range, value),
    });
  }

  /// The value [reading] has now, or null when it cannot be read.
  static Future<dynamic> _readValue(DeviceState reading, ControlKind kind, bool isGroup) async {
    try {
      final answers = await DeviceCommandsService.runCommands([reading.toCommand()]);
      if (answers.single.status_code != 200) return null;
      return controlValue(kind, answers.single.message, isGroup: isGroup);
    } catch (e, s) {
      ErrorReporter.log("Could not read back a control value", e, s);
      return null;
    }
  }

  /// The current values of the controls whose ids are [entries]. Each entry
  /// comes back with the fields it was sent with and its value and kind, and
  /// for a range its slider.
  static Future<String> _readStates(List<dynamic> entries) async {
    for (final item in entries) {
      final raw = item as Map<String, dynamic>;
      if (raw['deviceId'] == null) continue;
      _watched.add(_watchKey(raw['deviceId'], raw['serviceId'], raw['functionId'], raw['aspectId']));
    }
    final cache = <String, _Target>{};
    final outputs = <Map<String, dynamic>>[];
    final kinds = <ControlKind>[];
    final ranges = <ControlRange?>[];
    final isGroup = <bool>[];
    final commands = <DeviceCommand?>[];
    for (final item in entries) {
      final raw = item as Map<String, dynamic>;
      outputs.add(raw);
      final kind = raw['functionId'] == dotenv.env['FUNCTION_GET_ON_OFF_STATE'] ? ControlKind.toggle : ControlKind.range;
      kinds.add(kind);
      ranges.add(null);
      isGroup.add(false);
      commands.add(null);
      try {
        final entry = DeviceState.fromJson(raw);
        final target = await _targetOf(raw, cache);
        isGroup.last = target.isGroup;
        final reading = readingForEntry(entry, _aspectIdsOf(raw), target.states, isGroup: target.isGroup);
        if (reading != null && kind == ControlKind.range) {
          final control = controlOfReading(reading, target.states, isGroup: target.isGroup);
          if (control != null) ranges.last = controlRange(control, thermostat: target.thermostat);
        }
        // A reading the device type no longer has is still asked for with the
        // entry's own fields, as before, now bound to its device or group.
        final asked = reading ?? entry;
        if (reading == null) {
          if (target.isGroup) {
            asked.deviceGroup = target.group;
          } else {
            asked.deviceInstance = target.device;
          }
        }
        commands.last = asked.toCommand();
      } catch (e, s) {
        ErrorReporter.log("Could not resolve a control", e, s);
      }
    }
    final asked = [for (var i = 0; i < commands.length; i++) if (commands[i] != null) i];
    final values = <int, dynamic>{};
    if (asked.isNotEmpty) {
      try {
        final answers = await DeviceCommandsService.runCommands([for (final i in asked) commands[i]!]);
        for (var n = 0; n < asked.length; n++) {
          final answer = answers[n];
          if (answer.status_code == 200) {
            values[asked[n]] = controlValue(kinds[asked[n]], answer.message, isGroup: isGroup[asked[n]]);
          }
        }
      } catch (e, s) {
        // The controls stay without a value rather than the whole list failing.
        ErrorReporter.log("Could not read the control values", e, s);
      }
    }
    return json.encode([
      for (var i = 0; i < outputs.length; i++) withControlFields(outputs[i], kinds[i], ranges[i], values[i]),
    ]);
  }

  /// Opens the detail page of a device, or of a group when the argument is a
  /// map with `groupId`. A plain string is a device id, as sent before groups.
  static Future<void> _openDetailPage(dynamic argument) async {
    final context = navigatorKey.currentContext;
    if (context == null) throw "No root context";
    final String? groupId = argument is Map ? argument['groupId'] as String? : null;
    final DeviceInstance? device;
    DeviceGroup? group;
    if (groupId != null) {
      await _ensureMetadata();
      await _ensureNetworks();
      group = await _db().deviceGroups.where().idEqualTo(groupId).findFirst();
      group?.prepareStates();
      device = null;
    } else {
      final deviceId = argument is Map ? argument['deviceId'] : argument;
      device = await _db().deviceInstances.where().idEqualTo(deviceId as String).findFirst();
    }
    if (device == null && group == null) throw "Nothing found to open";
    if (!context.mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (context) => DetailPage(device, group)));
  }

  /// The controls of [controllingFunction] a toggle entry from the platform
  /// side means. The entry keeps only the first aspect, but also the service and
  /// path of its reading, which settle which state it is; the aspect rule of an
  /// old sensor pin only breaks a tie between readings at that place. Without
  /// such a reading, or when the tie stays, the entry itself picks the control
  /// by [DeviceState.legacyMatchAspects], as it did before aspect lists.
  static List<DeviceState> controlsForToggle(
      DeviceState entry, List<String>? entryAspectIds, List<DeviceState> states, String controllingFunction) {
    final samePlace = states
        .where((s) =>
            !s.isControlling &&
            s.functionId == entry.functionId &&
            s.serviceGroupKey == entry.serviceGroupKey &&
            s.serviceId == entry.serviceId &&
            s.path == entry.path)
        .toList(growable: false);
    final measurement = switch (samePlace.length) {
      0 => null,
      1 => samePlace.single,
      _ => DeviceState.resolveAspects(samePlace, entry.aspectId, entryAspectIds),
    };
    if (measurement != null) return measurement.controlsFor(states, controllingFunction);
    return DeviceState.legacyMatchAspects(
        states.where((s) =>
            s.isControlling && s.functionId == controllingFunction && s.serviceGroupKey == entry.serviceGroupKey),
        entry.aspectIds);
  }

  /// Tells the platform side that [state] has a new value, when it shows a
  /// control for it: an on/off reading, or one a single control with a range
  /// sets. Every reading the app loads or receives live passes here, so one
  /// without a shown control returns before any lookup.
  static void handleDeviceStateUpdate(DeviceState state) async {
    if (state.deviceId == null) return;
    if (!_watched.contains(_watchKey(state.deviceId, state.serviceId, state.functionId, state.aspectId))) return;
    final ControlEntry? entry;
    if (state.functionId == dotenv.env['FUNCTION_GET_ON_OFF_STATE']) {
      entry = ControlEntry(state, ControlKind.toggle);
    } else if (!state.isControlling) {
      final device = state.deviceInstance;
      final control = device == null ? null : controlOfReading(state, device.states, isGroup: false);
      final range =
          control == null ? null : controlRange(control, thermostat: deviceIsThermostat(device!));
      entry = range == null ? null : ControlEntry(state, ControlKind.range, range);
    } else {
      entry = null;
    }
    if (entry == null) return;
    try {
      await controlMethodChannel.invokeMethod(
          "toggleEvent", json.encode(controlEntryJson(entry, controlValue(entry.kind, state.value, isGroup: false))));
    } on MissingPluginException {
      // pass
    }
  }
}
