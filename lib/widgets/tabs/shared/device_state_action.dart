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
import 'package:logger/logger.dart';
import 'package:mobile_app/shared/characteristic_conversion.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/config/functions/function_config.dart';
import 'package:mobile_app/models/content_variable.dart';
import 'package:mobile_app/models/device_command_response.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/services/device_commands.dart';
import 'package:mobile_app/widgets/shared/toast.dart';

final _logger = Logger(printer: SimplePrinter());

/// Runs the action behind a device state — toggling a switch, setting a value,
/// and so on — then refreshes the measurements it affects.
///
/// Extracted from the device detail page so the sensors page can offer the same
/// controls without duplicating the command logic.
///
/// [element] may be either a controlling state (acted on directly) or a
/// readable one (its related controlling state is resolved via the function
/// config). [states] must be all states of the device or group, since related
/// controlling and measuring states are looked up in it.
///
/// The measurements refreshed afterwards are those the control pairs with
/// ([ControlPairing.pairedControls]). For a control that pairs with none,
/// [isGroup] selects them: for groups all related controlling functions count,
/// for a single device only the one matching the current value. [setState] is
/// handed to the function config's input builder, [notifyEntity] signals the
/// owning device/group so its widgets rebuild.
///
/// A non-null [value] is sent as the input instead of asking in the dialog,
/// for the inline controls of the detail page. It is dropped, not queued, when
/// a reading the control acts on is still transitioning: commands are not
/// idempotent, and the caller's control shows the reading again.
Future<void> performDeviceStateAction({
  required BuildContext context,
  required DeviceConnectionStatus? connectionStatus,
  required DeviceState element,
  required List<DeviceState> states,
  required bool isGroup,
  required StateSetter setState,
  required VoidCallback notifyEntity,
  dynamic value,
}) async {
  if (connectionStatus == DeviceConnectionStatus.offline) {
    Toast.showToastNoContext("Device is offline");
    return;
  }
  if (!element.isControlling) {
    final control = resolveControllingState(element, states);
    if (control == null) return;
    element = control;
  }
  final functionConfig = functionConfigs[element.functionId] ?? FunctionConfigDefault(element.functionId);
  final function = AppState().platformFunctions[element.functionId];

  if (function == null) {
    const err = "Function not found";
    Toast.showToastNoContext(err);
    _logger.e("$err: ${element.functionId}");
    return;
  }

  if (element.transitioning) {
    return; // avoid double presses
  }
  final (:paired, :related) = _readingsOf(element, states, isGroup);
  final List<int> transitioningStates = paired.isNotEmpty ? paired : related;
  final List<CommandCallback> commandCallbacks = [];
  for (final i in transitioningStates) {
    commandCallbacks.add(CommandCallback(states[i].toCommand(), (value) {
      states[i].transitioning = false;
      value = value as DeviceCommandResponse;
      if (value.status_code != 200) {
        _logger.e("${value.status_code}: ${value.message}");
        return;
      }
      if (value.message is List && value.message.length == 1) {
        states[i].value = value.message[0];
      } else {
        states[i].value = value.message;
      }
    }));
  }

  dynamic input;
  final hasInput = AppState().concepts[function.concept_id]?.getBaseCharacteristic().hasInput() ?? false;
  if (hasInput && value != null) {
    if (transitioningStates.any((i) => states[i].transitioning)) return;
    input = value;
  } else if (hasInput) {
    final current = _dialogStartValue(element, transitioningStates, states, functionConfig, isGroup);
    Widget? content = functionConfig.build(context, setState, current);
    if (content == null) {
      const err = "Function Config missing build()";
      Toast.showToastNoContext(err);
      _logger.e("$err: ${element.functionId}");
      return;
    }
    input = await showAdaptiveDialog(
      context: context,
      builder: (_) => AlertDialog.adaptive(
        title: const Text('Configure'),
        content: content,
        actions: <Widget>[
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          TextButton(child: const Text('OK'), onPressed: () => Navigator.pop(context, functionConfig.getConfiguredValue())),
        ],
      ),
    );
    if (input == null) {
      return; // canceled
    }
  }
  element.transitioning = true;
  for (var i in transitioningStates) {
    states[i].transitioning = true;
  }
  notifyEntity();
  final List<DeviceCommandResponse> responses = [];
  if (!await DeviceCommandsService.runCommandsSecurely([element.toCommand(input)], responses)) {
    element.transitioning = false;
    for (var i in transitioningStates) {
      states[i].transitioning = false;
    }
    notifyEntity();
    return;
  }
  assert(responses.length == 1);
  if (responses[0].status_code != 200) {
    element.transitioning = false;
    for (var i in transitioningStates) {
      states[i].transitioning = false;
    }
    notifyEntity();
    const err = "Error running command";
    Toast.showToastNoContext(err);
    _logger.e("$err: ${responses[0].message}");
    return;
  }
  element.transitioning = false;
  notifyEntity();

  // refresh changed measurements
  notifyEntity();
  responses.clear();
  if (!await DeviceCommandsService.runCommandsSecurely(commandCallbacks.map((e) => e.command).toList(growable: false), responses, false)) {
    for (var i in transitioningStates) {
      states[i].transitioning = false;
    }
    notifyEntity();
    return;
  }
  assert(responses.length == commandCallbacks.length);
  for (var i = 0; i < responses.length; i++) {
    commandCallbacks[i].callback(responses[i]);
  }
  notifyEntity();
}

/// The indexes in [states] of the readings [control] acts on, and of those that
/// relate to it by function. A control that pairs with none keeps a row of its
/// own and refreshes every reading of a related function in its service group
/// instead.
({List<int> paired, List<int> related}) _readingsOf(DeviceState control, List<DeviceState> states, bool isGroup) {
  final List<int> paired = [];
  final List<int> related = [];
  for (var i = 0; i < states.length; i++) {
    if (states[i].isControlling || states[i].serviceGroupKey != control.serviceGroupKey) {
      continue;
    }
    // From the control's side an input with the role Reading keeps the reading
    // it picks, as its start value and read-back ([ControlPairing.pairedControls]).
    if (states[i].pairedControls(states, control.functionId).any((c) => identical(c, control))) {
      paired.add(i);
    }
    var measuringFunctionConfig = functionConfigs[states[i].functionId];
    measuringFunctionConfig ??= FunctionConfigDefault(states[i].functionId);

    List<String>? refreshingMeasurementFunctionIds;
    if (isGroup) {
      refreshingMeasurementFunctionIds = measuringFunctionConfig.getAllRelatedControllingFunctions();
    } else {
      refreshingMeasurementFunctionIds = [measuringFunctionConfig.getRelatedControllingFunction(states[i].value) ?? ''];
    }
    if (refreshingMeasurementFunctionIds?.contains(control.functionId) ?? false) {
      related.add(i);
    }
  }
  return (paired: paired, related: related);
}

dynamic _startValue(List<int> readings, List<DeviceState> states, FunctionConfig config, bool isGroup) {
  dynamic current = readings.length == 1 ? states[readings[0]].value : null;
  // A group reads one value per device. The input starts with the value they
  // share, none when they differ. A list-typed value is a list already, so
  // for a group of one device it cannot be told apart and stays as it is.
  if (isGroup && current is List && config.characteristic?.type != ContentVariable.list) {
    current = commonValue(current);
  }
  return current;
}

/// The dialog's start value in the characteristic it works in: the reading
/// is in its own function's characteristic, which may differ. Empty when there
/// is no conversion, since a number in the wrong unit would be sent as is.
dynamic _dialogStartValue(
    DeviceState control, List<int> readings, List<DeviceState> states, FunctionConfig config, bool isGroup) {
  final start = _startValue(readings, states, config, isGroup);
  if (start == null || readings.length != 1) return start;
  final reading = states[readings.single];
  final from = readingCharacteristicId(reading.functionId);
  final to = config.characteristic?.id;
  if (from == null || to == null) return null;
  final functions = AppState().platformFunctions;
  return convertCharacteristic(start, from, to,
          conceptIds: [functions[reading.functionId]?.concept_id, functions[control.functionId]?.concept_id])
      ?.value;
}

/// The value the input of [control] starts with, in the characteristic of its
/// function config: that of the one reading the control acts on, a group's as
/// the value all devices share. Null when there is no single reading or no
/// common value. The dialog of [performDeviceStateAction] and the inline
/// controls of the detail page both start here, so both send the same payload.
dynamic controlStartValue(DeviceState control, List<DeviceState> states, {required bool isGroup}) {
  final FunctionConfig config;
  try {
    config = functionConfigs[control.functionId] ?? FunctionConfigDefault(control.functionId);
  } catch (_) {
    // A concept without its base characteristic has no input to start.
    return null;
  }
  final (:paired, :related) = _readingsOf(control, states, isGroup);
  return _startValue(paired.isNotEmpty ? paired : related, states, config, isGroup);
}

/// The readings in [states] that [control] acts on: those it pairs with, else
/// those of a related function in its service group, as the readings that
/// [performDeviceStateAction] marks as transitioning.
List<DeviceState> readingsOfControl(DeviceState control, List<DeviceState> states, {required bool isGroup}) {
  final (:paired, :related) = _readingsOf(control, states, isGroup);
  return [for (final i in paired.isNotEmpty ? paired : related) states[i]];
}

/// The controlling state that acts on the readable [measurement] given its
/// current value, among all [states] of its device or group. Null, after a
/// toast, when there is none or more than one. [controllingFunction] replaces
/// the function the value would select.
DeviceState? resolveControllingState(DeviceState measurement, List<DeviceState> states,
    [String? controllingFunction]) {
  final functionConfig = functionConfigs[measurement.functionId] ?? FunctionConfigDefault(measurement.functionId);
  controllingFunction ??= functionConfig.getRelatedControllingFunction(measurement.value);
  if (controllingFunction == null) {
    const err = "Could not find related controlling function";
    Toast.showToastNoContext(err);
    _logger.e(err);
    return null;
  }
  final controllingStates = measurement.controlsFor(states, controllingFunction);
  if (controllingStates.isEmpty) {
    const err = "Found no controlling service, check device type!";
    Toast.showToastNoContext(err);
    _logger.e(err);
    return null;
  }
  if (controllingStates.length > 1) {
    const err = "Found more than one controlling service, check device type!";
    Toast.showToastNoContext(err);
    _logger.e(err);
    return null;
  }
  return controllingStates.first;
}

/// The controlling state of a group that acts on its reading [state] given its
/// current value, among all [states] of the group, or null when there is not
/// exactly one. Without a toast, so a caller can leave a control passive.
///
/// A group's reading is not paired by aspect as a device's is
/// ([resolveControllingState]), since no group criterion satisfies that
/// lookup. Handing the result to [performDeviceStateAction] puts it on its
/// `isControlling` branch and skips the lookup.
///
/// [target] replaces the controlling function the value selects.
DeviceState? resolveGroupControl(DeviceState state, List<DeviceState> states, [String? target]) {
  final config = functionConfigs[state.functionId] ?? FunctionConfigDefault(state.functionId);
  target ??= config.getRelatedControllingFunction(state.value);
  if (target == null) return null;
  final candidates = states.where((s) => s.isControlling && s.functionId == target).toList(growable: false);
  // More than one means the group spans device classes that each bring their
  // own control; there is no single command to send, so leave it alone rather
  // than switch an arbitrary subset.
  if (candidates.length != 1) return null;
  // An input that feeds a measured value to the devices sets no reading.
  if (isReadingInput(candidates.single)) return null;
  return candidates.first;
}

/// Toggles an on/off [measurement] through its controlling state, then reads
/// the measurement back. Unlike [performDeviceStateAction] it asks for no input,
/// refreshes only [measurement] (the one value a device list row shows) and
/// toasts a failed read-back with the backend's message.
///
/// [controllingFunction] replaces the function the current value selects.
/// [measurement] is transitioning from the command until this returns, on
/// every path. Returns whether the value was read back.
Future<bool> toggleDeviceState({
  required DeviceConnectionStatus? connectionStatus,
  required DeviceState measurement,
  required List<DeviceState> states,
  required VoidCallback notifyEntity,
  String? controllingFunction,
}) async {
  if (connectionStatus == DeviceConnectionStatus.offline) {
    Toast.showToastNoContext("Device is offline");
    return false;
  }
  if (measurement.transitioning) {
    return false; // avoid double presses
  }
  final control = resolveControllingState(measurement, states, controllingFunction);
  if (control == null) return false;
  return toggleThroughControl(measurement: measurement, control: control, notifyEntity: notifyEntity);
}

/// Runs [control]'s command and reads [measurement] back, with the feedback of
/// [toggleDeviceState]. For a caller that has resolved the control itself, such
/// as a group's.
///
/// [measurement] is transitioning from the command until this returns, on
/// every path. Returns whether the value was read back.
Future<bool> toggleThroughControl({
  required DeviceState measurement,
  required DeviceState control,
  required VoidCallback notifyEntity,
}) async {
  // No await between this check and setting the flag below, so a second press
  // cannot slip in between.
  if (measurement.transitioning) {
    return false; // avoid double presses
  }
  measurement.transitioning = true;
  notifyEntity();
  try {
    final List<DeviceCommandResponse> responses = [];
    if (!await DeviceCommandsService.runCommandsSecurely([control.toCommand()], responses)) {
      return false;
    }
    assert(responses.length == 1);
    if (responses[0].status_code != 200) {
      final err = "Error running command: ${responses[0].message}";
      Toast.showToastNoContext(err);
      _logger.e(err);
      return false;
    }
    responses.clear();
    if (!await DeviceCommandsService.runCommandsSecurely([measurement.toCommand()], responses, false)) {
      return false;
    }
    assert(responses.length == 1);
    if (responses[0].status_code != 200) {
      final err = "Error running command: ${responses[0].message}";
      Toast.showToastNoContext(err);
      _logger.e(err);
      return false;
    }
    final message = responses[0].message;
    measurement.value = message is List && message.length == 1 ? message[0] : message;
    return true;
  } finally {
    measurement.transitioning = false;
    notifyEntity();
  }
}
