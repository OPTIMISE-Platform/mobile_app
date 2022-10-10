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

import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'function_config.dart';

class FunctionConfigGetLowerPowerInjectionLimit extends FunctionConfigDefault {
  FunctionConfigGetLowerPowerInjectionLimit() : super(dotenv.env['FUNCTION_GET_LOWER_POWER_INJECTION_LIMIT'] ?? "");

  @override
  String? getRelatedControllingFunction(_) {
    return dotenv.env['FUNCTION_SET_LOWER_POWER_INJECTION_LIMIT'];
  }

  @override
  List<String>? getAllRelatedControllingFunctions() {
    final f = dotenv.env['FUNCTION_SET_LOWER_POWER_INJECTION_LIMIT'];
    return f == null ? null : [f];
  }

}

class FunctionConfigGetUpperPowerInjectionLimit extends FunctionConfigDefault {
  FunctionConfigGetUpperPowerInjectionLimit() : super(dotenv.env['FUNCTION_GET_UPPER_POWER_INJECTION_LIMIT'] ?? "");

  @override
  String? getRelatedControllingFunction(_) {
    return dotenv.env['FUNCTION_SET_UPPER_POWER_INJECTION_LIMIT'];
  }

  @override
  List<String>? getAllRelatedControllingFunctions() {
    final f = dotenv.env['FUNCTION_SET_UPPER_POWER_INJECTION_LIMIT'];
    return f == null ? null : [f];
  }

}
