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
import 'package:logger/logger.dart';

import 'package:mobile_app/models/characteristic.dart';

class RGB {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  static Widget build(BuildContext context, Characteristic characteristic, StateSetter setState) {
    var _color = _getColor(characteristic);
    void setter(Color c) => setState(() {
          _color = c;
          characteristic.value = <String, int>{"r": c.red, "g": c.green, "b": c.blue};
        });
    return Column(mainAxisSize: MainAxisSize.min, children: [
      ColorPicker(
        pickerColor: _color,
        onColorChanged: (c) {
          _color = c;
          characteristic.value = <String, int>{"r": c.red, "g": c.green, "b": c.blue};
        },
        enableAlpha: false,
        displayThumbColor: false,
        portraitOnly: false,
        paletteType: PaletteType.hueWheel,
        labelTypes: [],
      ),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        _getQuickButton(Colors.red, setter),
        _getQuickButton(Colors.green, setter),
        _getQuickButton(Colors.blue, setter),
        _getQuickButton(Colors.white, setter),
        _getQuickButton(const Color.fromARGB(255, 253, 244, 220), setter),
      ])
    ]);
  }

  static Color _getColor(Characteristic characteristic) {
    var value = characteristic.value;
    if (value == null) {
      if (characteristic.sub_characteristics?.length == 3) {
        value = Map<String, dynamic>();
        for(var sub in characteristic.sub_characteristics!) {
          value[sub.name] = sub.value;
        }
      } else {
        return Colors.white;
      }
    }
    if (value is! Map<String, dynamic>) {
      _logger.w("value is not map: $value");
      return Colors.white;
    }
    if (!value.containsKey("r") || !value.containsKey("b") || !value.containsKey("g")) {
      _logger.w("value does not contains keys r, b and g: $value");
      return Colors.white;
    }
    return Color.fromARGB(255, value['r'] ?? 0, value['g'] ?? 0, value['b'] ?? 0);
  }

  static Widget _getQuickButton(Color c, void Function(Color c) set) {
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
      onPressed: () => set(c),
      cupertino: (_, __) => CupertinoIconButtonData(padding: EdgeInsets.zero),
    );
  }
}
