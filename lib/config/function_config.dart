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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/config/get_timestamp.dart';
import 'package:mobile_app/config/set_color.dart';
import 'package:mobile_app/config/set_off_state.dart';
import 'package:mobile_app/config/set_on_state.dart';
import 'package:mobile_app/services/settings.dart';

import '../app_state.dart';
import '../models/characteristic.dart';
import '../models/content_variable.dart';
import '../util/math_list.dart';
import 'get_color.dart';
import 'get_on_off_state.dart';
import 'get_temperature.dart';

final Map<String?, FunctionConfig> functionConfigs = {
  dotenv.env['FUNCTION_GET_ON_OFF_STATE']: FunctionConfigGetOnOffState(),
  dotenv.env['FUNCTION_SET_ON_STATE']: FunctionConfigSetOnState(),
  dotenv.env['FUNCTION_SET_OFF_STATE']: FunctionConfigSetOffState(),
  dotenv.env['FUNCTION_SET_COLOR']: FunctionConfigSetColor(),
  dotenv.env['FUNCTION_GET_COLOR']: FunctionConfigGetColor(),
  dotenv.env['FUNCTION_GET_TIMESTAMP']: FunctionConfigGetTimestamp(),
  dotenv.env['FUNCTION_GET_TEMPERATURE']: FunctionConfigGetTemperature(),
};

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
    dynamic preferredNotnull = value.firstWhere((element) => element != null, orElse:  () => null);
    return value.every((e) => (e is num && preferredNotnull is num && roundNumbersString(e) == roundNumbersString(preferredNotnull)) || e == preferredNotnull || e == null)
        ? roundNumbersString(preferredNotnull)
        : preferredNotnull is num
            ? roundNumbersString(minList(value)) + " - " + roundNumbersString(maxList(value))
            : "-";
  } else {
    return value == null || (value is List && value.isEmpty) ? "-" : roundNumbersString(value);
  }
}

abstract class FunctionConfig {
  String? getRelatedControllingFunction(dynamic value);

  List<String>? getAllRelatedControllingFunctions();

  Widget? displayValue(dynamic value, BuildContext context);

  dynamic getConfiguredValue();

  Widget? build(BuildContext context, [dynamic value]);
}

class FunctionConfigDefault implements FunctionConfig {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  final String _functionId;

  final List<Widget> _fields = [];
  dynamic _result;

  FunctionConfigDefault(this._functionId);

  @override
  Widget? build(BuildContext context, [dynamic value]) {
    final characteristic = AppState().nestedFunctions[_functionId]?.concept.base_characteristic;
    if (characteristic == null) {
      return null;
    }
    _result = {};
    _fields.clear();
    _walkTree(context, "", characteristic, value ?? characteristic.value);

    return Column(
      children: _fields,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
    );
  }

  _walkTree(BuildContext context, String path, Characteristic characteristic, dynamic value) {
    switch (characteristic.type) {
      case ContentVariable.FLOAT:
        if (value is List) value = value[0];
        _fields.add(const Divider());
        if (characteristic.min_value != null && characteristic.max_value != null) {
          _fields.add(Text(characteristic.name + (characteristic.display_unit != "" ? (" (" + characteristic.display_unit + ")") : "")));
          _fields.add(StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                    width: MediaQuery.of(context).size.width,
                    child: PlatformSlider(
                      onChanged: (double newValue) {
                        _insertValueIntoResult(newValue, path);
                        setState(() => value = newValue);
                      },
                      max: characteristic.max_value!,
                      min: characteristic.min_value!,
                      value: value is double
                          ? value
                          : value is int
                              ? value.toDouble()
                              : characteristic.min_value!,
                    )),
                Text(value is double ? (value as double).toStringAsFixed(2) : value?.toString() ?? characteristic.min_value!.toString()),
              ]);
            },
          ));
        } else {
          _fields.add(defaultTextFormField(characteristic, value, path, (value) {
            double doubleValue = 0;
            try {
              doubleValue = double.parse(value ?? "");
            } catch (e) {
              return "no decimal value";
            }
            if (characteristic.min_value != null && doubleValue < characteristic.min_value!) {
              return "value smaller than " + characteristic.min_value.toString();
            }
            if (characteristic.max_value != null && doubleValue > characteristic.max_value!) {
              return "value bigger than " + characteristic.max_value.toString();
            }
          }, (v) => double.parse(v ?? ""), const TextInputType.numberWithOptions(signed: true, decimal: true)));
        }
        break;
      case ContentVariable.INTEGER:
        if (value is List) value = value[0];
        _fields.add(const Divider());
        if (characteristic.min_value != null && characteristic.max_value != null) {
          _fields.add(Text(characteristic.name + (characteristic.display_unit != "" ? (" (" + characteristic.display_unit + ")") : "")));
          _fields.add(StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                    width: MediaQuery.of(context).size.width,
                    child: PlatformSlider(
                      onChanged: (double newValue) {
                        _insertValueIntoResult(newValue.toInt(), path);
                        setState(() => value = newValue.toInt());
                      },
                      max: characteristic.max_value!,
                      min: characteristic.min_value!,
                      value: value is int ? value.toDouble() : characteristic.min_value!,
                    )),
                Text(value?.toString() ?? characteristic.min_value!.toInt().toString()),
              ]);
            },
          ));
        } else {
          _fields.add(defaultTextFormField(characteristic, value, path, (value) {
            if (value == null) {
              return "no empty values";
            }
            if (value.contains(".") || value.contains(",")) {
              return "no decimal numbers";
            }
            int intValue = 0;
            try {
              intValue = int.parse(value);
            } catch (e) {
              return "invalid number";
            }
            if (characteristic.min_value != null && intValue < characteristic.min_value!) {
              return "value smaller than " + characteristic.min_value!.toInt().toString();
            }
            if (characteristic.max_value != null && intValue > characteristic.max_value!) {
              return "value bigger than " + characteristic.max_value!.toInt().toString();
            }
          }, (v) => int.parse(v ?? ""), const TextInputType.numberWithOptions(signed: true)));
        }
        break;
      case ContentVariable.STRING:
        if (value is List) value = value[0];
        _fields.add(const Divider());
        _fields.add(defaultTextFormField(characteristic, value, path, null, (v) => v));
        break;
      case ContentVariable.BOOLEAN:
        if (value is List) value = value[0];
        _fields.add(const Divider());
        _fields.add(Row(children: [
          Expanded(
              child: Text(
            characteristic.name + (characteristic.display_unit != "" ? (" (" + characteristic.display_unit + ")") : ""),
            textAlign: TextAlign.left,
          )),
          StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return PlatformSwitch(
                onChanged: (bool newValue) {
                  _insertValueIntoResult(newValue, path);
                  setState(() => value = newValue);
                },
                value: value,
              );
            },
          ),
        ]));
        break;
      case ContentVariable.STRUCTURE:
        characteristic.sub_characteristics?.forEach((sub) {
          var subPath = sub.name;
          if (path.isNotEmpty) {
            subPath = path + "." + subPath;
          }
          _walkTree(context, subPath, sub, value != null ? value[sub.name] : null);
        });
    }
  }

  _insertValueIntoResult(dynamic value, String path) {
    if (path == "") {
      _result = value;
      return;
    }
    final pathParts = path.split(".");
    var subResult = _result;
    for (var i = 0; i < pathParts.length - 1; i++) {
      if (subResult[pathParts[i]] == null) {
        subResult[pathParts[i]] = {};
      }
      subResult = subResult[pathParts[i]];
    }
    subResult[pathParts[pathParts.length - 1]] = value;
  }

  @override
  Widget? displayValue(value, BuildContext context) {
    return null;
  }

  @override
  String? getRelatedControllingFunction(value) {
    final conceptId = AppState().nestedFunctions[_functionId]?.concept.id;
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
    final conceptId = AppState().nestedFunctions[_functionId]?.concept.id;
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

  @override
  dynamic getConfiguredValue() {
    return _result;
  }

  PlatformTextFormField defaultTextFormField(
      Characteristic characteristic, dynamic value, String path, String? Function(String?)? validator, dynamic Function(String?) parse,
      [TextInputType? keyboardType]) {
    return PlatformTextFormField(
      hintText: characteristic.name,
      initialValue: value?.toString(),
      keyboardType: keyboardType,
      autovalidateMode: AutovalidateMode.always,
      validator: validator,
      onChanged: (value) {
        try {
          _insertValueIntoResult(parse(value), path);
        } catch (e) {
          _logger.d("error parsing user input");
        }
      },
      material: (_, __) => MaterialTextFormFieldData(
        decoration: InputDecoration(
          suffixText: characteristic.display_unit,
          labelText: characteristic.name,
        ),
      ),
      cupertino: (_, __) => CupertinoTextFormFieldData(
        prefix: Text(characteristic.name + (characteristic.display_unit != "" ? (" (" + characteristic.display_unit + ")") : "")),
      ),
    );
  }
}
