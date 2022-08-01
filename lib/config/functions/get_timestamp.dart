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
import 'package:intl/intl.dart';
import 'package:mobile_app/config/functions/function_config.dart';

class FunctionConfigGetTimestamp extends FunctionConfig {
  FunctionConfigGetTimestamp() {
    functionId = dotenv.env["FUNCTION_GET_TIMESTAMP"] ?? "";
  }

  static final _format = DateFormat.yMd().add_jms();

  @override
  Widget? displayValue(value, BuildContext context) {
    if (value is List) {
      final List<Text> children = [];
      for (var element in value) {
        children.add(Text(formatTimestamp(element), style: const TextStyle(fontStyle: FontStyle.italic)));
      }
      return Row(children: children);
    }
    return Text(formatTimestamp(value), style: const TextStyle(fontStyle: FontStyle.italic));
  }

  String formatTimestamp(dynamic value) {
    if (value is List) {
      final List<String> children = [];
      for (var element in value) {
        children.add(formatTimestamp(element));
      }
      return children.join("\n");
    }
    return _format.format(DateTime.parse(value).toLocal());
  }

  @override
  String? getRelatedControllingFunction(value) {
    return null;
  }

  @override
  List<String>? getAllRelatedControllingFunctions() {
    return null;
  }
}
