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
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/config/function_config.dart';

class FunctionConfigGetColor implements FunctionConfig {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );
  @override
  Widget? build(BuildContext context, [dynamic value]) {
    return null;
  }

  @override
  Widget? displayValue(value) {
    if (value is! Map<String, dynamic>) {
      if (value is List) {
        return Row(children: value.map((e) => displayValue(e)!).toList(growable: false), mainAxisSize: MainAxisSize.min);
      }
      _logger.w("value is not map or list: " + value.toString());
      return null;
    }
    if (!value.containsKey("r") || !value.containsKey("b") || !value.containsKey("g")) {
      _logger.w("value does not contains keys r, b and g: " + value.toString());
      return null;
    }
    return Icon(Icons.palette, color: Color.fromARGB(255, value['r'] ?? 0, value['g'] ?? 0, value['b'] ?? 0));
  }

  @override
  Icon? getIcon(value) {
    if (value is! Map<String, dynamic>) {
      _logger.w("value is not map: " + value.toString());
      return null;    }
    if (!value.containsKey("r") || !value.containsKey("b") || !value.containsKey("g")) {
      _logger.w("value does not contains keys r, b and g: " + value.toString());
      return null;
    }
    return Icon(Icons.palette, color: Color.fromARGB(255, value['r']!, value['g']!, value['b']!));
  }

  @override
  String? getRelatedControllingFunction(value) {
    return dotenv.env['FUNCTION_SET_COLOR'];
  }

  @override
  List<String>? getAllRelatedControllingFunctions() {
    return [dotenv.env['FUNCTION_SET_COLOR'] ?? ''];
  }

  @override
  getConfiguredValue() {
    return null;
  }

}
