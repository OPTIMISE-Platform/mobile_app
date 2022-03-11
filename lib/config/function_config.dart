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

final Map<String?, FunctionConfig> functionConfigs = {
  dotenv.env['FUNCTION_GET_ON_OFF_STATE']: FunctionConfig((dynamic value) {
    if (value is bool && value) {
      return dotenv.env['FUNCTION_SET_OFF_STATE'];
    }
    if (value is bool && !value) {
      return dotenv.env['FUNCTION_SET_ON_STATE'];
    }
  }, (dynamic value) {
    if (value is bool && value) {
      return const Icon(Icons.power_outlined);
    }
    if (value is bool && !value) {
      return const Icon(Icons.power_off_outlined);
    }
  }, (dynamic value) {
    if (value is bool && value) {
      return const Icon(Icons.power_outlined);
    }
    if (value is bool && !value) {
      return const Icon(Icons.power_off_outlined);
    }
    return Text(value.toString());
  }),
  dotenv.env['FUNCTION_SET_ON_STATE']: FunctionConfig(null, (_) => const Icon(Icons.power_outlined), null),
  dotenv.env['FUNCTION_SET_OFF_STATE']: FunctionConfig(null, (_) => const Icon(Icons.power_off_outlined), null),
};

class FunctionConfig {
  String? Function(dynamic)? getRelatedControllingFunction;
  Icon? Function(dynamic) getIcon;
  Widget Function(dynamic)? displayValue;

  FunctionConfig(this.getRelatedControllingFunction, this.getIcon, this.displayValue);
}
