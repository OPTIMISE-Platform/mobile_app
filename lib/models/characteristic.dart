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
import 'package:flutter/widgets.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/models/content_variable.dart';

import 'package:mobile_app/config/characteristics/characteristic_config.dart';

part 'characteristic.g.dart';

@JsonSerializable()
class Characteristic {
  String id, name, display_unit;
  ContentType type;
  double? min_value, max_value;
  dynamic value;
  List<Characteristic>? sub_characteristics;
  List<dynamic>? allowed_values;

  Characteristic(
      this.id, this.name, this.type, this.min_value, this.max_value, this.value, this.sub_characteristics, this.display_unit, this.allowed_values);

  factory Characteristic.fromJson(Map<String, dynamic> json) => _$CharacteristicFromJson(json);

  Map<String, dynamic> toJson() => _$CharacteristicToJson(this);

  Characteristic clone() {
    final List<Characteristic> subs = [];
    sub_characteristics?.forEach((sub) => subs.add(sub.clone()));
    return Characteristic(id, name, type, min_value, max_value, value, subs, display_unit, allowed_values);
  }

  String? value_label; // not in API, only locally used for Characteristic/Smart Service Parameter Duality

  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  final List<Widget> _fields = [];

  Widget build(BuildContext context, StateSetter setState, {bool skipConfig = false}) {
    if (!skipConfig && characteristicConfigs.containsKey(id)) {
      return characteristicConfigs[id]!(context, this, setState);
    }

    _fields.clear();
    _walkTree(context, "", this, value ?? value, setState);

    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _fields,
    );
    return SingleChildScrollView(
        child: PlatformWidget(
      cupertino: (_, __) => Material(
        child: column,
      ),
      material: (_, __) => column,
    ));
  }

  _walkTree(BuildContext context, String path, Characteristic characteristic, dynamic value, void Function(void Function()) setState) {
    switch (characteristic.type) {
      case ContentVariable.float:
        if (value is List) value = value[0];
        final dynamic existingValue = _getValue(path);
        if (existingValue != null) value = existingValue;
        _fields.add(const Divider());
        if (characteristic.min_value != null && characteristic.max_value != null) {
          _fields.add(Text(characteristic.name + (characteristic.display_unit != "" ? (" (${characteristic.display_unit})") : "")));
          _fields.add(StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                    width: MediaQuery.of(context).size.width,
                    child: PlatformSlider(
                      onChanged: (double newValue) {
                        _insertValueIntoResult(newValue, path, setState);
                        setState(() => value = newValue);
                      },
                      max: characteristic.max_value!,
                      min: characteristic.min_value!,
                      value: value is double
                          ? value
                          : value is int
                              ? value.toDouble()
                              : characteristic.min_value!,
                    )),
                Text(value is double ? (value as double).toStringAsFixed(2) : value?.toString() ?? characteristic.min_value!.toString()),
              ]);
            },
          ));
        } else if (characteristic.allowed_values != null && characteristic.allowed_values!.isNotEmpty) {
          _fields.add(StatefulBuilder(
              builder: (context, setState) => SizedBox(
                  width: MediaQuery.of(context).size.width,
                  child: DropdownButton<double>(
                    value: value,
                    items: characteristic.allowed_values!
                        .map((e) => DropdownMenuItem<double>(
                              value: e,
                              child: Text(e),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() {
                      value = v;
                      _insertValueIntoResult(v, path, setState);
                    }),
                  ))));
        } else {
          _fields.add(defaultTextFormField(characteristic, value, path, (value) {
            double doubleValue = 0;
            try {
              doubleValue = double.parse(value ?? "");
            } catch (e) {
              return "no decimal value";
            }
            if (characteristic.min_value != null && doubleValue < characteristic.min_value!) {
              return "value smaller than ${characteristic.min_value}";
            }
            if (characteristic.max_value != null && doubleValue > characteristic.max_value!) {
              return "value bigger than ${characteristic.max_value}";
            }
          }, (v) => double.parse(v ?? ""), setState, const TextInputType.numberWithOptions(signed: true, decimal: true)));
        }
        _insertValueIntoResult(value, path, setState, ignoreExisting: true);
        break;
      case ContentVariable.integer:
        if (value is List) value = value[0];
        final dynamic existingValue = _getValue(path);
        if (existingValue != null) value = existingValue;
        _fields.add(const Divider());
        if (characteristic.min_value != null && characteristic.max_value != null) {
          _fields.add(Text(characteristic.name + (characteristic.display_unit != "" ? (" (${characteristic.display_unit})") : "")));
          _fields.add(StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                    width: MediaQuery.of(context).size.width,
                    child: PlatformSlider(
                      onChanged: (double newValue) {
                        _insertValueIntoResult(newValue.toInt(), path, setState);
                        setState(() => value = newValue.toInt());
                      },
                      max: characteristic.max_value!,
                      min: characteristic.min_value!,
                      value: value is int ? value.toDouble() : characteristic.min_value!,
                    )),
                Text(value?.toString() ?? characteristic.min_value!.toInt().toString()),
              ]);
            },
          ));
        } else if (characteristic.allowed_values != null && characteristic.allowed_values!.isNotEmpty) {
          _fields.add(StatefulBuilder(
              builder: (context, setState) => SizedBox(
                  width: MediaQuery.of(context).size.width,
                  child: DropdownButton<int>(
                    value: value,
                    items: characteristic.allowed_values!
                        .map((e) => DropdownMenuItem<int>(
                              value: e,
                              child: Text(e),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() {
                      value = v;
                      _insertValueIntoResult(v, path, setState);
                    }),
                  ))));
        } else {
          _fields.add(defaultTextFormField(characteristic, value, path, (value) {
            if (value == null) {
              return "no empty values";
            }
            if (value.contains(".") || value.contains(",")) {
              return "no decimal numbers";
            }
            int intValue = 0;
            try {
              intValue = int.parse(value);
            } catch (e) {
              return "invalid number";
            }
            if (characteristic.min_value != null && intValue < characteristic.min_value!) {
              return "value smaller than ${characteristic.min_value!.toInt()}";
            }
            if (characteristic.max_value != null && intValue > characteristic.max_value!) {
              return "value bigger than ${characteristic.max_value!.toInt()}";
            }
          }, (v) => int.parse(v ?? ""), setState, const TextInputType.numberWithOptions(signed: true)));
        }
        _insertValueIntoResult(value, path, setState, ignoreExisting: true);
        break;
      case ContentVariable.string:
        if (value is List) value = value[0];
        final dynamic existingValue = _getValue(path);
        if (existingValue != null) value = existingValue;
        _fields.add(const Divider());
        if (characteristic.allowed_values != null && characteristic.allowed_values!.isNotEmpty) {
          _fields.add(StatefulBuilder(
              builder: (context, setState) => SizedBox(
                  width: MediaQuery.of(context).size.width,
                  child: DropdownButton<String>(
                    value: value,
                    items: characteristic.allowed_values!
                        .map((e) => DropdownMenuItem<String>(
                              value: e,
                              child: Text(e),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() {
                      value = v;
                      _insertValueIntoResult(v, path, setState);
                    }),
                  ))));
        } else {
          _fields.add(defaultTextFormField(characteristic, value, path, null, (v) => v, setState));
        }
        _insertValueIntoResult(value, path, setState, ignoreExisting: true);
        break;
      case ContentVariable.boolean:
        if (value is List) value = value[0];
        final dynamic existingValue = _getValue(path);
        if (existingValue != null) value = existingValue;
        _fields.add(const Divider());
        _fields.add(Row(children: [
          Expanded(
              child: Text(
            characteristic.name + (characteristic.display_unit != "" ? (" (${characteristic.display_unit})") : ""),
            textAlign: TextAlign.left,
          )),
          StatefulBuilder(
            builder: (BuildContext context, StateSetter setState) {
              return PlatformSwitch(
                onChanged: (bool newValue) {
                  _insertValueIntoResult(newValue, path, setState);
                  setState(() => value = newValue);
                },
                value: value ?? false,
              );
            },
          ),
        ]));
        _insertValueIntoResult(value, path, setState, ignoreExisting: true);
        break;
      case ContentVariable.structure:
        final dynamic existingValue = _getValue(path);
        if (existingValue != null) value = existingValue;
        characteristic.sub_characteristics?.forEach((sub) {
          var subPath = sub.name;
          if (path.isNotEmpty) {
            subPath = "$path.$subPath";
          }
          _walkTree(context, subPath, sub, value != null ? value[sub.name] ?? sub.value : sub.value, setState);
        });
        break;
      case ContentVariable.list:
        _fields.add(const Divider());
        final bool hasStarElement = characteristic.sub_characteristics != null &&
            characteristic.sub_characteristics!.isNotEmpty &&
            characteristic.sub_characteristics![0].name == "*";
        if (hasStarElement) {
          _fields.add(ListTile(
              title: Text(characteristic.name),
              trailing: PlatformIconButton(
                icon: Icon(PlatformIcons(context).add),
                onPressed: () {
                  final clone = characteristic.sub_characteristics![0].clone();
                  clone.name = characteristic.sub_characteristics!.length.toString();
                  clone.id = "";
                  characteristic.sub_characteristics!.add(clone);
                  setState(() {});
                },
              )));
        } else {
          _fields.add(Text(characteristic.name));
        }

        for (var i = 0; i < (characteristic.sub_characteristics?.length ?? 0); i++) {
          final sub = characteristic.sub_characteristics![i];
          if (sub.name != "*") {
            var subPath = "[${hasStarElement ? i - 1 : i}]";
            if (path.isNotEmpty) {
              subPath = "$path.$subPath";
            }
            _walkTree(context, subPath, sub,
                value != null ? (value is List ? (value.length > i ? value[i] : null) : value[sub.name]) ?? sub.value : sub.value, setState);
          }
        }
    }
  }

  _insertValueIntoResult(dynamic value, String path, StateSetter setState, {bool ignoreExisting = false}) {
    if (path == "") {
      if (this.value != value) {
        WidgetsBinding.instance.addPostFrameCallback((_) => setState(() {}));
      }
      this.value = value;
      return;
    }
    final pathParts = path.split(".");
    this.value ??= {};
    var subResult = this.value;
    for (var i = 0; i < pathParts.length - 1; i++) {
      if (subResult[pathParts[i]] == null) {
        if (pathParts.length > i + 1 && pathParts[i + 1].startsWith("[")) {
          subResult[pathParts[i]] = <dynamic>[];
        } else {
          subResult[pathParts[i]] = {};
        }
      }
      if (pathParts[i].startsWith("[")) {
        subResult = subResult.elementAt(int.parse(pathParts[i].replaceFirst("[", "").replaceFirst("]", "")));
      } else {
        subResult = subResult[pathParts[i]];
      }
    }
    if (pathParts[pathParts.length - 1].startsWith("[")) {
      int i = int.parse(pathParts[pathParts.length - 1].replaceFirst("[", "").replaceFirst("]", ""));
      if (subResult.length <= i) {
        subResult.insert(i, value);
        WidgetsBinding.instance.addPostFrameCallback((_) => setState(() {}));
      } else if (subResult[i] == null || !ignoreExisting) {
        if (subResult[i] != value) {
          WidgetsBinding.instance.addPostFrameCallback((_) => setState(() {}));
        }
        subResult[i] = value;
      }
    } else if (subResult[pathParts[pathParts.length - 1]] == null || !ignoreExisting) {
      if (subResult[pathParts[pathParts.length - 1]] != value) {
        WidgetsBinding.instance.addPostFrameCallback((_) => setState(() {}));
      }
      subResult[pathParts[pathParts.length - 1]] = value;
    }
  }

  dynamic _getValue(String path) {
    if (value == null) {
      return null;
    }
    if (path == "") {
      return value;
    }
    final pathParts = path.split(".");
    var subResult = value;
    for (var i = 0; i < pathParts.length - 1; i++) {
      if (subResult[pathParts[i]] == null) {
        return null;
      }
      if (pathParts[i].startsWith("[")) {
        subResult = subResult.elementAt(int.parse(pathParts[i].replaceFirst("[", "").replaceFirst("]", "")));
      } else {
        subResult = subResult[pathParts[i]];
      }
    }
    if (pathParts[pathParts.length - 1].startsWith("[")) {
      int i = int.parse(pathParts[pathParts.length - 1].replaceFirst("[", "").replaceFirst("]", ""));
      return (subResult as List).length > i ? subResult[i] : null;
    } else {
      return subResult[pathParts[pathParts.length - 1]];
    }
  }

  PlatformTextFormField defaultTextFormField(Characteristic characteristic, dynamic value, String path, String? Function(String?)? validator,
      dynamic Function(String?) parse, StateSetter setState,
      [TextInputType? keyboardType]) {
    return PlatformTextFormField(
      hintText: characteristic.name,
      initialValue: value?.toString(),
      keyboardType: keyboardType,
      autovalidateMode: AutovalidateMode.always,
      validator: validator,
      onChanged: (value) {
        try {
          _insertValueIntoResult(parse(value), path, setState);
        } catch (e) {
          _logger.d("error parsing user input");
        }
      },
      material: (_, __) => MaterialTextFormFieldData(
        decoration: InputDecoration(
          suffixText: characteristic.display_unit,
          labelText: characteristic.name,
        ),
      ),
      cupertino: (_, __) => CupertinoTextFormFieldData(
        prefix: Text(characteristic.name + (characteristic.display_unit != "" ? (" (${characteristic.display_unit})") : "")),
      ),
    );
  }
}
