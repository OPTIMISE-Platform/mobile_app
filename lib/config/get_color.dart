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

import '../exceptions/argument_exception.dart';

class FunctionConfigGetColor implements FunctionConfig {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  @override
  Widget? build(BuildContext context, [dynamic value]) {
    return null;
  }

  @override
  Widget? displayValue(value, BuildContext context) {
    if (value is! Map<String, dynamic>) {
      if (value is List) {
        if (value.every((element) => element.toString() == value[0].toString())) {
          return displayValue(value[0], context);
        }
        return Stack(
          alignment: AlignmentDirectional.center,
          children: [
            ShaderMask(
              child: const Icon(Icons.palette, color: Colors.black), //maximum contrast
              shaderCallback: (Rect bounds) =>
                  LinearGradient(colors: value.map((e) => _getColor(e)).toList(growable: false), begin: Alignment.topLeft, end: Alignment.bottomRight)
                      .createShader(bounds.deflate(MediaQuery.textScaleFactorOf(context) * 8.5)),
              blendMode: BlendMode.srcATop,
            ),
            const Icon(Icons.palette_outlined, color: Colors.grey),
          ],
        );
      }
      _logger.w("value is not map or list: " + value.toString());
      return null;
    }
    if (!value.containsKey("r") || !value.containsKey("b") || !value.containsKey("g")) {
      _logger.w("value does not contains keys r, b and g: " + value.toString());
      return null;
    }
    return Stack(
      alignment: AlignmentDirectional.center,
      children: [
        Icon(
          Icons.palette,
          color: Color.fromARGB(255, value['r'] ?? 0, value['g'] ?? 0, value['b'] ?? 0),
        ),
        const Icon(Icons.palette_outlined, color: Colors.grey),
      ],
    );
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

  Color _getColor(Map<String, dynamic> value) {
    if (!value.containsKey("r") || !value.containsKey("b") || !value.containsKey("g")) {
      throw ArgumentException("value does not contains keys r, b and g: " + value.toString());
    }
    return Color.fromARGB(255, value['r'] ?? 0, value['g'] ?? 0, value['b'] ?? 0);
  }
}
