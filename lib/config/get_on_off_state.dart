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
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:mobile_app/config/function_config.dart';

class FunctionConfigGetOnOffState implements FunctionConfig {
  @override
  Widget? build(BuildContext context, [dynamic value]) {
    return null;
  }

  @override
  Widget? displayValue(value, BuildContext context) {
    if (value is bool && value) {
      return const Icon(Icons.power_outlined);
    }
    if (value is bool && !value) {
      return const Icon(Icons.power_off_outlined);
    }
    if (value is List && value.isNotEmpty) {
      if (value.every((element) => element == value[0])) {
        return displayValue(value[0], context);
      }
      return Icon(PlatformIcons(context).remove);
    }

    return null;
  }

  @override
  String? getRelatedControllingFunction(value) {
    if ((value is bool && value) || (value is List && !value.contains(false))) {
      return dotenv.env['FUNCTION_SET_OFF_STATE'];
    }
    if ((value is bool && !value) || (value is List && !value.contains(true))) {
      return dotenv.env['FUNCTION_SET_ON_STATE'];
    }
    return null;
  }

  @override
  List<String>? getAllRelatedControllingFunctions() {
    return [dotenv.env['FUNCTION_SET_OFF_STATE'] ?? '', dotenv.env['FUNCTION_SET_ON_STATE'] ?? ''];
  }

  @override
  getConfiguredValue() {
    return null;
  }

}
