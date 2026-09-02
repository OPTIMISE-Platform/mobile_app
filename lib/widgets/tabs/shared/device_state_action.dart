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
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/config/functions/function_config.dart';
import 'package:mobile_app/models/device_command_response.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/models/function.dart';
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
/// [isGroup] selects how affected measurements are determined: for groups all
/// related controlling functions count, for a single device only the one
/// matching the current value. [setState] is handed to the function config's
/// input builder, [notifyEntity] signals the owning device/group so its widgets
/// rebuild.
Future<void> performDeviceStateAction({
  required BuildContext context,
  required DeviceConnectionStatus? connectionStatus,
  required DeviceState element,
  required List<DeviceState> states,
  required bool isGroup,
  required StateSetter setState,
  required VoidCallback notifyEntity,
}) async {
  if (connectionStatus == DeviceConnectionStatus.offline) {
    Toast.showToastNoContext("Device is offline");
    return;
  }
  FunctionConfig? functionConfig;
  PlatformFunction? function;
  if (!element.isControlling) {
    functionConfig = functionConfigs[element.functionId] ?? FunctionConfigDefault(element.functionId);
    function = AppState().platformFunctions[functionConfig.getRelatedControllingFunction(element.value)];

    final controllingFunction = functionConfig.getRelatedControllingFunction(element.value);
    if (controllingFunction == null) {
      const err = "Could not find related controlling function";
      Toast.showToastNoContext(err);
      _logger.e(err);
      return;
    }
    final controllingStates = states.where((state) =>
        state.isControlling &&
        state.functionId == controllingFunction &&
        state.serviceGroupKey == element.serviceGroupKey &&
        state.aspectId == element.aspectId);
    if (controllingStates.isEmpty) {
      const err = "Found no controlling service, check device type!";
      Toast.showToastNoContext(err);
      _logger.e(err);
      return;
    }
    if (controllingStates.length > 1) {
      const err = "Found more than one controlling service, check device type!";
      Toast.showToastNoContext(err);
      _logger.e(err);
      return;
    }
    element = controllingStates.first;
    functionConfig = functionConfigs[element.functionId] ?? FunctionConfigDefault(element.functionId);
  } else {
    functionConfig = functionConfigs[element.functionId] ?? FunctionConfigDefault(element.functionId);
    function = AppState().platformFunctions[element.functionId];
  }

  if (function == null) {
    const err = "Function not found";
    Toast.showToastNoContext(err);
    _logger.e("$err: ${element.functionId}");
    return;
  }

  if (element.transitioning) {
    return; // avoid double presses
  }
  final List<CommandCallback> commandCallbacks = [];
  final List<int> transitioningStates = [];
  for (var i = 0; i < states.length; i++) {
    if (states[i].isControlling) {
      continue;
    }
    var measuringFunctionConfig = functionConfigs[states[i].functionId];
    measuringFunctionConfig ??= FunctionConfigDefault(states[i].functionId);

    List<String>? refreshingMeasurementFunctionIds;
    if (isGroup) {
      refreshingMeasurementFunctionIds = measuringFunctionConfig.getAllRelatedControllingFunctions();
    } else {
      refreshingMeasurementFunctionIds = [measuringFunctionConfig.getRelatedControllingFunction(states[i].value) ?? ''];
    }
    refreshingMeasurementFunctionIds ??= [];

    if (element.serviceGroupKey == states[i].serviceGroupKey && refreshingMeasurementFunctionIds.contains(element.functionId)) {
      transitioningStates.add(i);
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
  }

  dynamic input;
  if (AppState().concepts[function.concept_id]?.getBaseCharacteristic().hasInput() ?? false) {
    Widget? content = functionConfig.build(context, setState, transitioningStates.length == 1 ? states[transitioningStates[0]].value : null);
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
          TextButton(child: const Text('OK'), onPressed: () => Navigator.pop(context, functionConfig!.getConfiguredValue())),
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
