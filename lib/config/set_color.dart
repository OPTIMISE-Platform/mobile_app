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
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:mobile_app/config/function_config.dart';
import 'package:mobile_app/exceptions/argument_exception.dart';

class FunctionConfigSetColor implements FunctionConfig {
  Color _color = Colors.white;

  @override
  Widget? build(BuildContext context, [dynamic value]) {
    _color = _getColor(value);
    return StatefulBuilder(builder: (context, setState) => Column(mainAxisSize: MainAxisSize.min, children: [
      ColorPicker(
        pickerColor: _color,
        onColorChanged: (color) {
          _color = color;
        },
        enableAlpha: false,
        displayThumbColor: false,
        portraitOnly: false,
        paletteType: PaletteType.hueWheel,
        labelTypes: [],
      ),
      Row(children: [
        IconButton(icon: const Icon(Icons.square), onPressed: () => setState(() => _color = Colors.red), color: Colors.red),
        IconButton(icon: const Icon(Icons.square), onPressed: () => setState(() => _color = Colors.green), color: Colors.green),
        IconButton(icon: const Icon(Icons.square), onPressed: () => setState(() => _color = Colors.blue), color: Colors.blue),
        IconButton(icon: const Icon(Icons.square), onPressed: () => setState(() => _color = Colors.white), color: Colors.black12),
        IconButton(icon: const Icon(Icons.square), onPressed: () => setState(() => _color = const Color.fromARGB(255, 253, 244, 220)), color: const Color.fromARGB(255, 253, 244, 220)),
      ], mainAxisAlignment: MainAxisAlignment.center)
    ]));
  }

  @override
  Widget? displayValue(value) {
    return null;
  }

  @override
  Icon? getIcon(value) {
    return const Icon(Icons.palette);
  }

  @override
  String? getRelatedControllingFunction(value) {
    return null;
  }

  @override
  getConfiguredValue() {
    return {"r": _color.red, "g": _color.green, "b": _color.blue};
  }

  Color _getColor(dynamic value) {
    if (value == null) {
      return Colors.white;
    }
    if (value is! Map<String, dynamic>) {
      throw ArgumentException("value is not map: " + value.toString());
    }
    if (!value.containsKey("r") || !value.containsKey("b") || !value.containsKey("g")) {
      throw ArgumentException("value does not contains keys r, b and g: " + value.toString());
    }
    return Color.fromARGB(255, value['r']!, value['g']!, value['b']!);
  }
}
