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
import 'package:mobile_app/config/functions/get_timestamp.dart';
import 'package:mobile_app/config/functions/set_color.dart';
import 'package:mobile_app/config/functions/set_off_state.dart';
import 'package:mobile_app/config/functions/set_on_state.dart';
import 'package:mobile_app/services/settings.dart';

import '../../models/characteristic.dart';
import '../../shared/math_list.dart';
import 'get_color.dart';
import 'get_on_off_state.dart';
import 'get_temperature.dart';

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
    dotenv.env['FUNCTION_GET_TEMPERATURE']: FunctionConfigGetTemperature()..init(),
  };
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

abstract class FunctionConfig {
  String functionId = "";
  late final Characteristic? characteristic;

  String? getRelatedControllingFunction(dynamic value);

  List<String>? getAllRelatedControllingFunctions();

  Widget? displayValue(dynamic value, BuildContext context);

  @nonVirtual
  dynamic getConfiguredValue() {
    return characteristic?.value;
  }

  @nonVirtual
  Widget? build(BuildContext context, StateSetter setState, [dynamic value]) {
    if (value != null) {
      characteristic?.value = value;
    }
    return characteristic?.build(context, setState);
  }

  init() {
    final String? preferred = Settings.getFunctionPreferredCharacteristicId(functionId);
    if (preferred != null) {
      characteristic = AppState().characteristics[preferred]?.clone();
    } else {
      characteristic = AppState().nestedFunctions[functionId]?.concept.base_characteristic?.clone();
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
    final conceptId = AppState().nestedFunctions[functionId]?.concept.id;
    if (conceptId == null) {
      return null;
    }
    final controllingFunctions =
        AppState().nestedFunctions.values.where((element) => element.isControlling() && element.concept.id == conceptId).toList(growable: false);
    if (controllingFunctions.length == 1) {
      return controllingFunctions[0].id;
    }

    return null;
  }

  @override
  List<String>? getAllRelatedControllingFunctions() {
    final conceptId = AppState().nestedFunctions[functionId]?.concept.id;
    if (conceptId == null) {
      return null;
    }
    return AppState()
        .nestedFunctions
        .values
        .where((element) => element.isControlling() && element.concept.id == conceptId)
        .toList(growable: false)
        .map((e) => e.id)
        .toList(growable: false);
  }
}
