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

import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/exceptions/no_network_exception.dart';
import 'package:mobile_app/models/function.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/services/device_classes.dart';
import 'package:mobile_app/services/device_commands.dart';
import 'package:mobile_app/services/device_types.dart';
import 'package:mobile_app/services/device_types_perm_search.dart';
import 'package:mobile_app/services/devices.dart';
import 'package:mobile_app/services/functions.dart';
import 'package:mutex/mutex.dart';

import 'models/device_class.dart';
import 'models/device_command_response.dart';
import 'models/device_instance.dart';
import 'models/device_type.dart';
import 'widgets/toast.dart';

class AppState extends ChangeNotifier {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  bool _metaInitialized = false;

  final Map<String, DeviceClass> deviceClasses = {};
  final Mutex _deviceClassesMutex = Mutex();

  final Map<String, DeviceTypePermSearch> deviceTypesPermSearch = {};
  final Mutex _deviceTypesPermSearchMutex = Mutex();

  final Map<String, DeviceType> deviceTypes = {};

  final Map<String, NestedFunction> nestedFunctions = {};
  final Mutex _nestedFunctionsMutex = Mutex();

  String _deviceSearchText = '';

  int totalDevices = -1;
  final Mutex _totalDevicesMutex = Mutex();

  final List<DeviceInstance> devices = <DeviceInstance>[];
  final Mutex _devicesMutex = Mutex();

  int _deviceClassArrIndex = 0;
  int _classOffset = 0;

  bool loggedIn() => Auth.tokenValid();

  bool loggingIn() => Auth.loggingIn();

  initAllMeta(BuildContext context) async {
    await loadDeviceClasses(context);
    await loadDeviceTypes(context);
    await loadNestedFunctions(context);
    _metaInitialized = true;
  }

  loadDeviceClasses(BuildContext context) async {
    final locked = _deviceClassesMutex.isLocked;
    _deviceClassesMutex.acquire();
    if (locked) {
      return deviceClasses;
    }
    for (var element
        in (await DeviceClassesService.getDeviceClasses(context, this))) {
      deviceClasses[element.id] = element;
    }
    notifyListeners();
    _deviceClassesMutex.release();
  }

  loadDeviceTypes(BuildContext context) async {
    final locked = _deviceTypesPermSearchMutex.isLocked;
    _deviceTypesPermSearchMutex.acquire();
    if (locked) {
      return deviceTypesPermSearch;
    }
    for (var element
        in (await DeviceTypesPermSearchService.getDeviceTypes(context, this))) {
      deviceTypesPermSearch[element.id] = element;
    }
    notifyListeners();
    _deviceTypesPermSearchMutex.release();
  }

  loadNestedFunctions(BuildContext context) async {
    final locked = _nestedFunctionsMutex.isLocked;
    _nestedFunctionsMutex.acquire();
    if (locked) {
      return nestedFunctions;
    }
    for (var element
        in (await FunctionsService.getNestedFunctions(context, this))) {
      nestedFunctions[element.id] = element;
    }
    notifyListeners();
    _nestedFunctionsMutex.release();
  }

  updateTotalDevices(BuildContext context) async {
    _totalDevicesMutex.acquire();
    final total =
        await DevicesService.getTotalDevices(context, this, _deviceSearchText);
    if (total != totalDevices) {
      totalDevices = total;
      notifyListeners();
    }
  }

  searchDevices(String query, BuildContext context,
      [bool force = false]) async {
    if (!force && query == _deviceSearchText) {
      return;
    }
    _deviceClassArrIndex = 0;
    _classOffset = 0;
    if (devices.isNotEmpty) {
      devices.clear();
      notifyListeners();
    }
    _deviceSearchText = query;
    updateTotalDevices(context);
    loadDevices(context);
  }

  refreshDevices(BuildContext context) async {
    await searchDevices(_deviceSearchText, context, true);
  }

  loadDevices(BuildContext context,
      [int size = 50, bool skipMutex = false]) async {
    if (!skipMutex && _devicesMutex.isLocked) {
      return;
    }
    if (!skipMutex) _devicesMutex.acquire();

    if (!_metaInitialized) {
      await initAllMeta(context);
    }

    late final List<DeviceInstance> newDevices;
    try {
      List<String> deviceTypeIds = deviceTypesPermSearch.values
          .where((element) =>
              element.device_class_id ==
              deviceClasses.keys.elementAt(_deviceClassArrIndex))
          .map((e) => e.id)
          .toList(growable: false);

      newDevices = await DevicesService.getDevices(
          context, this, size, _classOffset, _deviceSearchText, deviceTypeIds);
    } catch (e) {
      _logger.e("Could not get devices: " + e.toString());
      Toast.showErrorToast(context, "Could not load devices");
      if (!skipMutex) _devicesMutex.release();
      return;
    }
    devices.addAll(newDevices);
    _classOffset += newDevices.length;
    if (newDevices.isNotEmpty) {
      notifyListeners();
      loadOnOffStates(context, newDevices); // no await => run in background
    }
    if (totalDevices < devices.length) {
      await updateTotalDevices(context); // when loadDevices called directly
    }
    if (newDevices.length < size &&
        deviceClasses.length - 1 > _deviceClassArrIndex) {
      _classOffset = 0;
      _deviceClassArrIndex++;
      loadDevices(context, size - newDevices.length, true);
    }
    if (!skipMutex) _devicesMutex.release();
  }

  loadDeviceType(BuildContext context, String id, [bool force = false]) async {
    if (!force && deviceTypes.containsKey(id)) {
      return;
    }
    final t = await DeviceTypesService.getDeviceType(context, this, id);
    if (t == null) {
      return;
    }
    deviceTypes[id] = t;
  }

  loadOnOffStates(BuildContext context, List<DeviceInstance> devices) async {
    await loadStates(context, devices, [dotenv.env['FUNCTION_GET_ON_OFF_STATE'] ?? '']);
  }

  loadStates(BuildContext context, List<DeviceInstance> devices, [List<String>? limitToFunctionIds]) async {
    final List<CommandCallback> commandCallbacks = [];
    for (var element in devices) {
      await loadDeviceType(context, element.device_type_id);
      element.prepareStates(deviceTypes[element.device_type_id]!);
      commandCallbacks.addAll(element.getStateFillFunctions(
          limitToFunctionIds));
    }
    if (commandCallbacks.isEmpty) {
      return;
    }
    final List<DeviceCommandResponse> result;
    try {
      result = await DeviceCommandsService.runCommands(context, this,
          commandCallbacks.map((e) => e.command).toList(growable: false));
    } on NoNetworkException {
      _logger.e("failed to loadAllStates: currently offline");
      rethrow;
    } catch(e) {
      _logger.e("failed to loadAllStates: " + e.toString());
      rethrow;
    }
    assert(result.length == commandCallbacks.length);
    for (var i = 0; i < commandCallbacks.length; i++) {
      if (result[i].status_code == 200) {
        commandCallbacks[i].callback(result[i].message);
      } else {
        _logger.e(result[i].status_code.toString() + ": " + result[i].message);
      }
    }
    notifyListeners();
  }

  @override
  void notifyListeners() {
    _logger.d("notifying listeners");
    super.notifyListeners();
  }
}
