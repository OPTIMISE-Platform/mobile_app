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
import 'package:mobile_app/config/functions/function_config.dart';

import 'package:mobile_app/exceptions/argument_exception.dart';
import 'package:mobile_app/shared/colour_value.dart';

class FunctionConfigGetColor extends FunctionConfig {
  FunctionConfigGetColor() {
    functionId = dotenv.env['FUNCTION_GET_COLOR'] ?? "";
  }

  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  @override
  Widget? displayValue(value, BuildContext context) {
    if (value is! Map && value is! String) {
      if (value is List) {
        if (value.every((element) => element.toString() == value[0].toString())) {
          return displayValue(value[0], context);
        }
        return Stack(
          alignment: AlignmentDirectional.center,
          children: [
            ShaderMask(
              shaderCallback: (Rect bounds) =>
                  LinearGradient(colors: value.map((e) => _getColor(e)).toList(growable: false), begin: Alignment.topLeft, end: Alignment.bottomRight)
                      .createShader(bounds.deflate(MediaQuery.textScalerOf(context).scale(8.5))),
              blendMode: BlendMode.srcATop,
              child: const Icon(Icons.palette, color: Colors.black),
            ),
            const Icon(Icons.palette_outlined, color: Colors.grey),
          ],
        );
      }
      _logger.w("value is not map or list: $value");
      return null;
    }
    final color = colourOf(value);
    if (color == null) {
      _logger.w("value is no color (r/g/b or h/s/b): $value");
      return null;
    }
    return Stack(
      alignment: AlignmentDirectional.center,
      children: [
        Icon(Icons.palette, color: color),
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

  Color _getColor(dynamic value) {
    final color = colourOf(value);
    if (color == null) throw ArgumentException("value is no color (r/g/b or h/s/b): $value");
    return color;
  }
}
