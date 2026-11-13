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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/config/functions/get_battery.dart';
import 'package:mobile_app/config/functions/get_timestamp.dart';
import 'package:mobile_app/config/functions/set_color.dart';
import 'package:mobile_app/config/functions/set_off_state.dart';
import 'package:mobile_app/config/functions/set_on_state.dart';
import 'package:mobile_app/services/settings.dart';

import 'package:mobile_app/models/aspect.dart';
import 'package:mobile_app/models/aspect_ids.dart';
import 'package:mobile_app/models/characteristic.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/shared/math_list.dart';
import 'package:mobile_app/config/functions/get_color.dart';
import 'package:mobile_app/config/functions/get_on_off_state.dart';
import 'package:mobile_app/config/functions/get_power_injection_limit.dart';

Map<String?, FunctionConfig> functionConfigs = _specialConfigs();

reinit() {
  functionConfigs = _specialConfigs();
}

Map<String?, FunctionConfig> _specialConfigs() {
  return {
    dotenv.env['FUNCTION_GET_ON_OFF_STATE']: FunctionConfigGetOnOffState()..init(),
    dotenv.env['FUNCTION_SET_ON_STATE']: FunctionConfigSetOnState()..init(),
    dotenv.env['FUNCTION_SET_OFF_STATE']: FunctionConfigSetOffState()..init(),
    dotenv.env['FUNCTION_SET_COLOR']: FunctionConfigSetColor()..init(),
    dotenv.env['FUNCTION_GET_COLOR']: FunctionConfigGetColor()..init(),
    dotenv.env['FUNCTION_GET_TIMESTAMP']: FunctionConfigGetTimestamp()..init(),
    dotenv.env['FUNCTION_GET_LOWER_POWER_INJECTION_LIMIT']: FunctionConfigGetLowerPowerInjectionLimit(),
    dotenv.env['FUNCTION_GET_UPPER_POWER_INJECTION_LIMIT']: FunctionConfigGetUpperPowerInjectionLimit(),
    dotenv.env['FUNCTION_GET_BATTERY_LEVEL']: FunctionConfigGetBatteryLevel(),
  };
}

/// The controlling functions that act on a reading of [functionId]. Builds no
/// default config, whose init fails on a concept without its base
/// characteristic; a special config answers even when it answers null.
List<String>? relatedControllingFunctionsOf(String functionId) {
  final special = functionConfigs[functionId];
  return special != null
      ? special.getAllRelatedControllingFunctions()
      : FunctionConfigDefault.relatedControllingFunctions(functionId);
}

/// Whether [id] is the aspect Reading, by its id or, for an instance with
/// other ids, its name.
bool isReadingAspect(String id) =>
    id == readingAspectId || joinAspectNames(AppState().aspects.values, [id]).toLowerCase() == 'reading';

/// Whether [state] carries the value role Reading.
bool hasReadingRole(DeviceState state) => state.aspectIds.any(isReadingAspect);

/// Whether [state] is an input with the value role Reading, such as a
/// thermostat's external temperature input. It feeds a measured value to the
/// device and is never the setting of a reading.
bool isReadingInput(DeviceState state) => state.isControlling && hasReadingRole(state);

extension ControlPairing on DeviceState {
  /// The controls of [controllingFunctionId] in [states] that act on this
  /// reading, with readings related to controls through the function configs.
  /// An input with the role Reading still claims its reading from other
  /// controls but is not returned ([isReadingInput]).
  List<DeviceState> controlsFor(Iterable<DeviceState> states, String controllingFunctionId) =>
      pairedControls(states, controllingFunctionId).where((c) => !isReadingInput(c)).toList(growable: false);

  /// [controlsFor] with inputs of the role Reading kept.
  List<DeviceState> pairedControls(Iterable<DeviceState> states, String controllingFunctionId) =>
      controlsAmong(states, controllingFunctionId, relatedControllingFunctionsOf);
}

String roundNumbersString(dynamic value) {
  int fractionDigits = Settings.getDisplayedFractionDigits();
  if (value is num && fractionDigits >= 0) {
    //toStringAsFixed to get a set number of fraction digits; regexp to remove trailing zeros
    return value.toStringAsFixed(fractionDigits).replaceAll(RegExp(r"([.]*0+)(?!.*\d)"), "");
  }
  return value.toString();
}

String formatValue(dynamic value) {
  if (value is List && value.isNotEmpty) {
    dynamic preferredNotnull = value.firstWhere((element) => element != null, orElse: () => null);
    return value.every((e) =>
            (e is num && preferredNotnull is num && roundNumbersString(e) == roundNumbersString(preferredNotnull)) ||
            e == preferredNotnull ||
            e == null)
        ? roundNumbersString(preferredNotnull)
        : preferredNotnull is num
            ? "${roundNumbersString(minList(value))} - ${roundNumbersString(maxList(value))}"
            : "-";
  } else {
    return value == null || (value is List && value.isEmpty) ? "-" : roundNumbersString(value);
  }
}

/// The value all devices of a group report in [values], or null when they
/// differ. Devices without a reading (null) are skipped, as in [formatValue].
/// Structures compare by their fields; nested ones count as different.
dynamic commonValue(List<dynamic> values) {
  final known = values.where((e) => e != null);
  if (known.isEmpty) return null;
  final first = known.first;
  bool same(dynamic e) => e == first || (e is Map && first is Map && mapEquals(e, first));
  return known.every(same) ? first : null;
}

abstract class FunctionConfig {
  String functionId = "";
  // Not final: [configCharacteristic] looks it up again while it is missing.
  Characteristic? characteristic;

  String? getRelatedControllingFunction(dynamic value);

  List<String>? getAllRelatedControllingFunctions();

  Widget? displayValue(dynamic value, BuildContext context);

  @nonVirtual
  dynamic getConfiguredValue() {
    return characteristic?.value;
  }

  /// The input for a command, starting from the current [value]. Null starts
  /// empty, also for a config kept across dialogs that still holds the last
  /// input.
  @nonVirtual
  Widget? build(BuildContext context, StateSetter setState, [dynamic value]) {
    characteristic?.value = value;
    return characteristic?.build(context, setState, focusInput: true);
  }

  init() {
    final String? preferred = Settings.getFunctionPreferredCharacteristicId(functionId);
    if (preferred != null) {
      characteristic = AppState().characteristics[preferred]?.clone();
    } else {
      characteristic = AppState().concepts[AppState().platformFunctions[functionId]?.concept_id]?.getBaseCharacteristic().clone();
    }
  }
}

class FunctionConfigDefault extends FunctionConfig {
  FunctionConfigDefault(String functionId) {
    super.functionId = functionId;
    init();
  }


  @override
  Widget? displayValue(value, BuildContext context) {
    return null;
  }

  @override
  String? getRelatedControllingFunction(value) {
    final conceptId = AppState().platformFunctions[functionId]?.concept_id;
    if (conceptId == null) {
      return null;
    }
    final controllingFunctions =
        AppState().platformFunctions.values.where((element) => element.isControlling() && element.concept_id == conceptId).toList(growable: false);
    if (controllingFunctions.length == 1) {
      return controllingFunctions[0].id;
    }

    return null;
  }

  @override
  List<String>? getAllRelatedControllingFunctions() => relatedControllingFunctions(functionId);

  /// The controlling functions sharing the concept of [functionId].
  static List<String>? relatedControllingFunctions(String functionId) {
    final conceptId = AppState().platformFunctions[functionId]?.concept_id;
    if (conceptId == null) {
      return null;
    }
    return AppState()
        .platformFunctions
        .values
        .where((element) => element.isControlling() && element.concept_id == conceptId)
        .toList(growable: false)
        .map((e) => e.id)
        .toList(growable: false);
  }
}

/// The characteristic [functionId]'s config works in. The shared configs are
/// built on first use, which can be before the concepts are loaded; a missing
/// characteristic is therefore looked up again.
Characteristic? configCharacteristic(String functionId) {
  final config = functionConfigs[functionId] ?? FunctionConfigDefault(functionId);
  if (config.characteristic == null) config.init();
  return config.characteristic;
}
