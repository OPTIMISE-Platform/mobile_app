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
import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:isar/isar.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/services/device_commands.dart';
import 'package:mobile_app/shared/isar.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/detail_page.dart';

import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/config/functions/function_config.dart';
import 'package:mobile_app/main.dart';
import 'package:mobile_app/models/device_state.dart';

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
          final resp = json
              .encode(devices.map((e) => e.states).expand((e) => e).where((e) => e.functionId == dotenv.env['FUNCTION_GET_ON_OFF_STATE']).toList());
          return resp;
        case "setToggle":
          final DeviceState state = DeviceState.fromJson(json.decode(call.arguments));
          final device = await isar!.deviceInstances.where().idEqualTo(state.deviceId!).findFirst();
          await AppState().loadDeviceType(device!.device_type_id);
          await device.prepareStates(AppState().deviceTypes[device.device_type_id]!);
          final controllingFunction = functionConfigs[dotenv.env['FUNCTION_GET_ON_OFF_STATE']]?.getRelatedControllingFunction(!(state.value as bool));
          final controllingStates = device.states
              .where((s) =>
                  s.isControlling &&
                  s.functionId == controllingFunction &&
                  s.serviceGroupKey == state.serviceGroupKey &&
                  s.aspectId == state.aspectId)
              .toList();
          if (controllingStates.isEmpty) {
            throw "Found no controlling service, check device type!";
          }
          if (controllingStates.length > 1) {
            throw "Found more than one controlling service, check device type!";
          }
          return json.encode(await DeviceCommandsService.runCommands([controllingStates[0].toCommand()]));
        case "getToggleStates":
          final List<dynamic> ljson = json.decode(call.arguments);
          final states = List.generate(ljson.length, (index) => DeviceState.fromJson(ljson[index] as Map<String, dynamic>)).toList();
          final res = await DeviceCommandsService.runCommands(states.map((e) => e.toCommand()).toList());
          for (var i = 0; i < states.length; i++) {
            if (res[i].status_code == 200) {
              states[i].value = res[i].message[0];
            }
          }
          return json.encode(states);
        case "openDetailPage":
          final device = await isar!.deviceInstances.where().idEqualTo(call.arguments).findFirst();
          if (navigatorKey.currentContext != null) {
            Navigator.push(
                navigatorKey.currentContext!, platformPageRoute(context: navigatorKey.currentContext!, builder: (context) => DetailPage(device, null)));
          } else {
            throw "No root context";
          }
          return null;
        default:
          throw MissingPluginException("not implemented");
      }
    });
  }

  static void handleDeviceStateUpdate(DeviceState state) async {
    if (state.deviceId != null && state.functionId == dotenv.env['FUNCTION_GET_ON_OFF_STATE']) {
      try {
        await controlMethodChannel.invokeMethod("toggleEvent", json.encode(state));
      } on MissingPluginException {
        // pass
      }
    }
  }
}
