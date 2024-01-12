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
import 'package:flutter_native_timezone/flutter_native_timezone.dart';

import 'package:mobile_app/models/characteristic.dart';

class TZ {
  static Widget build(BuildContext context, Characteristic characteristic, StateSetter setState) {
    if (characteristic.value == null) {
      FlutterNativeTimezone.getLocalTimezone().then((value) {
        if (characteristic.value == null) {
          characteristic.value = value;
          setState(() {});
        }
      });
    }
    return characteristic.build(context, setState, skipConfig: true);
  }
}
