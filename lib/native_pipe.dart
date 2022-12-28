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

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:isar/isar.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/shared/isar.dart';

import 'app_state.dart';

class NativePipe {
  static const MethodChannel controlMethodChannel = MethodChannel("flutter/controlMethodChannel");

  static void init() {
    controlMethodChannel.setMethodCallHandler((call) async {
      switch (call.method) {
        case "getToggleStateless":
          final devices = await isar!.deviceInstances.where().findAll();
          final List<Future> futures = [];
          devices.forEach((element) => futures.add(AppState()
              .loadDeviceType(element.device_type_id)
              .then((value) => element.prepareStates(AppState().deviceTypes[element.device_type_id]!))));
          await Future.wait(futures);
          return json.encode(devices.map((e) => e.states).expand((e) => e).where((e) => e.functionId == dotenv.env['FUNCTION_GET_ON_OFF_STATE']).toList());
        default:
          throw MissingPluginException("not implemented");
      }
    });
  }
}
