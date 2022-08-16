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
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:mobile_app/config/function_config.dart';
import 'package:mobile_app/exceptions/argument_exception.dart';

class FunctionConfigSetColor implements FunctionConfig {
  Color _color = Colors.white;

  @override
  Widget? build(BuildContext context, [dynamic value]) {
    if (value is List) value = value[0];
    _color = _getColor(value);
    return StatefulBuilder(
        builder: (context, setState) => Column(mainAxisSize: MainAxisSize.min, children: [
              ColorPicker(
                pickerColor: _color,
                onColorChanged: (color) {
                  _color = color;
                },
                enableAlpha: false,
                displayThumbColor: false,
                portraitOnly: false,
                paletteType: PaletteType.hueWheel,
                labelTypes: const [],
              ),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _getQuickButton(Colors.red, setState),
                _getQuickButton(Colors.green, setState),
                _getQuickButton(Colors.blue, setState),
                _getQuickButton(Colors.white, setState),
                _getQuickButton(const Color.fromARGB(255, 253, 244, 220), setState),
              ])
            ]));
  }

  @override
  Widget? displayValue(value, BuildContext context) {
    return const Icon(Icons.palette);
  }

  @override
  String? getRelatedControllingFunction(value) {
    return null;
  }

  @override
  List<String>? getAllRelatedControllingFunctions() {
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
      throw ArgumentException("value is not map: $value");
    }
    if (!value.containsKey("r") || !value.containsKey("b") || !value.containsKey("g")) {
      throw ArgumentException("value does not contains keys r, b and g: $value");
    }
    return Color.fromARGB(255, value['r'] ?? 0, value['g'] ?? 0, value['b'] ?? 0);
  }

  Widget _getQuickButton(Color c, void Function(void Function()) setState) {
    return PlatformIconButton(
      icon: Stack(
        alignment: AlignmentDirectional.center,
        children: [
          Icon(
            Icons.square,
            color: c,
          ),
          const Icon(Icons.square_outlined, color: Colors.grey),
        ],
      ),
      onPressed: () => setState(() => _color = c),
      cupertino: (_, __) => CupertinoIconButtonData(padding: EdgeInsets.zero),
    );
  }
}
