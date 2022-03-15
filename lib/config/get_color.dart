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
import 'package:mobile_app/config/function_config.dart';
import 'package:mobile_app/exceptions/argument_exception.dart';

class FunctionConfigGetColor implements FunctionConfig {
  @override
  Widget? build(BuildContext context, [dynamic value]) {
    return null;
  }

  @override
  Widget? displayValue(value) {
    if (value is! Map<String, dynamic>) {
      throw ArgumentException("value is not map: " + value.toString());
    }
    if (!value.containsKey("r") || !value.containsKey("b") || !value.containsKey("g")) {
      throw ArgumentException("value does not contains keys r, b and g: " + value.toString());
    }
    return Icon(Icons.palette, color: Color.fromARGB(255, value['r']!, value['g']!, value['b']!));
  }

  @override
  Icon? getIcon(value) {
   return null;
  }

  @override
  String? getRelatedControllingFunction(value) {
    return dotenv.env['FUNCTION_SET_COLOR'];
  }

  @override
  getConfiguredValue() {
    return null;
  }

}
