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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/config/function_config.dart';
import 'package:mobile_app/config/get_timestamp.dart';
import 'package:mobile_app/models/device_state.dart';
import 'package:mobile_app/models/function.dart';
import 'package:mobile_app/widgets/app_bar.dart';
import 'package:mobile_app/widgets/toast.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/device_command_response.dart';
import '../models/device_instance.dart';
import '../services/device_commands.dart';
import '../services/devices.dart';
import '../theme.dart';
import '../util/keyed_list.dart';

const int maxInt = (double.infinity is int) ? double.infinity as int : ~minInt;
const int minInt = (double.infinity is int) ? -double.infinity as int : (-1 << 63);

class DevicePage extends StatelessWidget {
  final int _stateDeviceIndex;

  const DevicePage(this._stateDeviceIndex, {Key? key}) : super(key: key);

  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  refresh(BuildContext context, AppState state) {
    _refresh(context, state, true);
  }

  _refresh(BuildContext context, AppState state, bool external) async {
    for (var element in state.devices[_stateDeviceIndex].states) {
      if (!element.isControlling) {
        element.value = null;
        element.transitioning = true;
      }
    }
    if (!external) state.notifyListeners(); // not allowed when just building the widget
    state.loadStates(context, [state.devices[_stateDeviceIndex]]);
  }

  _performAction(DeviceConnectionStatus connectionStatus, BuildContext context, DeviceState element, DeviceInstance device, AppState state) async {
    if (connectionStatus == DeviceConnectionStatus.offline) {
      Toast.showWarningToast(context, "Device is offline", const Duration(milliseconds: 750));
      return;
    }
    FunctionConfig? functionConfig;
    NestedFunction? function;
    if (!element.isControlling) {
      functionConfig = functionConfigs[element.functionId] ?? FunctionConfigDefault(state, element.functionId);
      function = state.nestedFunctions[functionConfig.getRelatedControllingFunction(element.value)];

      final controllingFunction = functionConfig.getRelatedControllingFunction(element.value);
      if (controllingFunction == null) {
        const err = "Could not find related controlling function";
        Toast.showErrorToast(context, err);
        _logger.e(err);
        return;
      }
      final controllingStates = device.states.where((state) =>
          state.isControlling &&
          state.functionId == controllingFunction &&
          state.serviceGroupKey == element.serviceGroupKey &&
          state.aspectId == element.aspectId);
      if (controllingStates.isEmpty) {
        const err = "Found no controlling service, check device type!";
        Toast.showErrorToast(context, err);
        _logger.e(err);
        return;
      }
      if (controllingStates.length > 1) {
        const err = "Found more than one controlling service, check device type!";
        Toast.showErrorToast(context, err);
        _logger.e(err);
        return;
      }
      element = controllingStates.first;
      functionConfig = functionConfigs[element.functionId] ?? FunctionConfigDefault(state, element.functionId);
    } else {
      functionConfig = functionConfigs[element.functionId] ?? FunctionConfigDefault(state, element.functionId);
      function = state.nestedFunctions[element.functionId];
    }

    if (function == null) {
      const err = "Function not found";
      Toast.showWarningToast(context, err, const Duration(milliseconds: 750));
      _logger.e(err + ": " + element.functionId);
      return;
    }

    if (element.transitioning) {
      return; // avoid double presses
    }
    final List<CommandCallback> commandCallbacks = [];
    final List<int> transitioningStates = [];
    for (var i = 0; i < device.states.length; i++) {
      if (device.states[i].isControlling) {
        continue;
      }
      var measuringFunctionConfig = functionConfigs[device.states[i].functionId];
      measuringFunctionConfig ??= FunctionConfigDefault(state, device.states[i].functionId);
      if (element.serviceGroupKey == device.states[i].serviceGroupKey &&
          measuringFunctionConfig.getRelatedControllingFunction(device.states[i].value) == element.functionId) {
        transitioningStates.add(i);
        commandCallbacks.add(CommandCallback(device.states[i].toCommand(device.id), (value) {
          device.states[i].transitioning = false;
          value = value as DeviceCommandResponse;
          if (value.status_code != 200) {
            _logger.e(value.status_code.toString() + ": " + value.message);
            return;
          }
          if (value.message is List && value.message.length == 1) {
            device.states[i].value = value.message[0];
          } else {
            device.states[i].value = value.message;
          }
        }));
      }
    }

    dynamic input;
    if (function.hasInput()) {
      Widget? content = functionConfig.build(context, transitioningStates.length == 1 ? device.states[transitioningStates[0]].value : null);
      if (content == null) {
        const err = "Function Config missing build()";
        Toast.showErrorToast(context, err, const Duration(milliseconds: 750));
        _logger.e(err + ": " + element.functionId);
        return;
      }
      input = await showPlatformDialog(
        context: context,
        builder: (_) => PlatformAlertDialog(
          title: const Text('Configure'),
          content: content,
          actions: <Widget>[
            PlatformDialogAction(
              child: PlatformText('Cancel'),
              onPressed: () => Navigator.pop(context),
            ),
            PlatformDialogAction(child: PlatformText('OK'), onPressed: () => Navigator.pop(context, functionConfig!.getConfiguredValue())),
          ],
        ),
      );
      if (input == null) {
        return; // canceled
      }
    }
    element.transitioning = true;
    for (var i in transitioningStates) {
      device.states[i].transitioning = true;
    }
    state.notifyListeners();
    final List<DeviceCommandResponse> responses = [];
    if (!await DeviceCommandsService.runCommandsSecurely(context, state, [element.toCommand(device.id, input)], responses)) {
      element.transitioning = false;
      for (var i in transitioningStates) {
        device.states[i].transitioning = false;
      }
      state.notifyListeners();
      return;
    }
    assert(responses.length == 1);
    if (responses[0].status_code != 200) {
      element.transitioning = false;
      for (var i in transitioningStates) {
        device.states[i].transitioning = false;
      }
      state.notifyListeners();
      const err = "Error running command";
      Toast.showErrorToast(context, err);
      _logger.e(err + ": " + responses[0].message.toString());
      return;
    }
    element.transitioning = false;
    state.notifyListeners();

    // refresh changed measurements
    state.notifyListeners();
    responses.clear();
    if (!await DeviceCommandsService.runCommandsSecurely(context, state, commandCallbacks.map((e) => e.command).toList(growable: false), responses)) {
      for (var i in transitioningStates) {
        device.states[i].transitioning = false;
      }
      state.notifyListeners();
      return;
    }
    assert(responses.length == commandCallbacks.length);
    for (var i = 0; i < responses.length; i++) {
      commandCallbacks[i].callback(responses[i]);
    }
    state.notifyListeners();
  }

  _displayTimestamp(DeviceState element, DeviceInstance device, BuildContext context) {
    try {
      final state = device.states.firstWhere((state) =>
          !state.isControlling &&
          state.serviceId == element.serviceId &&
          state.aspectId == element.aspectId &&
          state.functionId == dotenv.env["FUNCTION_GET_TIMESTAMP"]);
      Toast.showInformationToast(context, FunctionConfigGetTimestamp().formatTimestamp(state.value), const Duration(milliseconds: 1000));
    } catch (e) {
      _logger.w("Could not display timestamp: " + e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    _logger.d("Device Page opened for index " + _stateDeviceIndex.toString());

    return Consumer<AppState>(builder: (context, state, child) {
      if (state.devices.length - 1 < _stateDeviceIndex) {
        _logger.w("Device Page requested for device index that is not in AppState");
        return const SizedBox.shrink();
      }
      final device = state.devices[_stateDeviceIndex];
      final connectionStatus = device.getConnectionStatus();
      final _appBar = MyAppBar(device.name);
      if (state.devices.isEmpty) {
        state.loadDevices(context);
      }
      List<Widget> appBarActions = [];

      if (kIsWeb) {
        appBarActions.add(PlatformIconButton(
          onPressed: () => _refresh(context, state, false),
          icon: const Icon(Icons.refresh),
          cupertino: (_, __) => CupertinoIconButtonData(padding: EdgeInsets.zero),
        ));
      }
      appBarActions.addAll(MyAppBar.getDefaultActions(context));

      KeyedList<String, Widget> functionWidgets = KeyedList();
      final List<DeviceState> markedControllingStates = [];

      for (var element in device.states.where((element) => !element.isControlling)) {
        if (element.functionId == dotenv.env["FUNCTION_GET_TIMESTAMP"]) {
          continue;
        }

        final function = state.nestedFunctions[element.functionId];
        var functionConfig = functionConfigs[element.functionId] ?? FunctionConfigDefault(state, element.functionId);

        String title = function?.display_name ?? "MISSING_FUNCTION_NAME";
        if (title.isEmpty) title = function?.name ?? "MISSING_FUNCTION_NAME";

        final controllingFunctions = functionConfig.getAllRelatedControllingFunctions();
        Iterable<DeviceState>? controllingStates;
        if (controllingFunctions != null) {
          controllingStates = device.states.where((state) =>
              state.isControlling &&
              controllingFunctions.contains(state.functionId) &&
              state.serviceGroupKey == element.serviceGroupKey &&
              state.aspectId == element.aspectId);
        }
        if (controllingFunctions == null || controllingFunctions.isEmpty || controllingStates == null || controllingStates.isEmpty) {
          functionWidgets.insert(
            element.functionId,
            ListTile(
              onTap: () => _displayTimestamp(element, device, context),
              title: Text(title),
              trailing: element.transitioning
                  ? PlatformCircularProgressIndicator()
                  : functionConfig.displayValue(element.value) ??
                      Text(
                          element.value.toString() +
                              " " +
                              (state.nestedFunctions[element.functionId]?.concept.base_characteristic?.display_unit ?? ""),
                          style: const TextStyle(fontStyle: FontStyle.italic)),
            ),
          );
        } else {
          markedControllingStates.addAll(controllingStates);
          functionWidgets.insert(
            element.functionId,
            ListTile(
                onTap: () => _displayTimestamp(element, device, context),
                title: Text(title),
                trailing: element.transitioning
                    ? PlatformCircularProgressIndicator()
                    : functionConfig.getIcon(element.value) != null
                        ? IconButton(
                            icon: functionConfig.getIcon(element.value)!,
                            onPressed: connectionStatus == DeviceConnectionStatus.offline
                                ? null
                                : () => _performAction(
                                      connectionStatus,
                                      context,
                                      element,
                                      device,
                                      state,
                                    ),
                          )
                        : PlatformTextButton(
                            child: functionConfig.displayValue(element.value) ??
                                Text(element.value.toString() +
                                    " " +
                                    (state.nestedFunctions[element.functionId]?.concept.base_characteristic?.display_unit ?? "")),
                            onPressed: connectionStatus == DeviceConnectionStatus.offline
                                ? null
                                : () => _performAction(
                                      connectionStatus,
                                      context,
                                      element,
                                      device,
                                      state,
                                    ),
                          )),
          );
        }
      }

      for (var element in device.states.where((element) => element.isControlling && !markedControllingStates.contains(element))) {
        final function = state.nestedFunctions[element.functionId];
        var functionConfig = functionConfigs[element.functionId];

        String title = function?.display_name ?? "MISSING_FUNCTION_NAME";
        if (title.isEmpty) title = function?.name ?? "MISSING_FUNCTION_NAME";

        functionWidgets.insert(
          element.functionId,
          ListTile(
            title: Text(title),
            trailing: element.transitioning
                ? Center(child: PlatformCircularProgressIndicator())
                : IconButton(
                    splashRadius: 25,
                    icon: functionConfig?.getIcon(element.value) ?? const Icon(Icons.input),
                    onPressed: connectionStatus == DeviceConnectionStatus.offline
                        ? null
                        : () => _performAction(
                              connectionStatus,
                              context,
                              element,
                              device,
                              state,
                            ),
                  ),
          ),
        );
      }

      final List<Widget> widgets = [];
      final list = functionWidgets.list();
      list.sort((a, b) {
        if (a.k == dotenv.env['FUNCTION_GET_ON_OFF_STATE']) {
          return minInt;
        }
        if (b.k == dotenv.env['FUNCTION_GET_ON_OFF_STATE']) {
          return maxInt;
        }
        return a.k.compareTo(b.k);
      });
      for (var element in list) {
        widgets.add(const Divider());
        widgets.add(element.t);
      }

      final List<Widget> trailingHeader = [];

      if (connectionStatus == DeviceConnectionStatus.offline) {
        trailingHeader.add(Tooltip(message: "Device is offline", child: Icon(PlatformIcons(context).error, color: MyTheme.warnColor)));
      }
      trailingHeader.add(IconButton(icon: Icon(device.favorite ? PlatformIcons(context).favoriteSolid :
          PlatformIcons(context).favoriteOutline, color: device.favorite ? Colors.redAccent : null,), onPressed: () async {
        device.toggleFavorite();
        await DevicesService.saveDevice(context, state, device);
        state.notifyListeners();
      },));

      return PlatformScaffold(
        appBar: _appBar.getAppBar(context, appBarActions),
        body: RefreshIndicator(
          onRefresh: () => _refresh(context, state, false),
          child: Scrollbar(
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16.0),
              children: [
                ListTile(
                  // header
                  leading: Container(
                    height: MediaQuery.of(context).textScaleFactor * 48,
                    width: MediaQuery.of(context).textScaleFactor * 48,
                    decoration: BoxDecoration(color: const Color(0xFF6c6c6c), borderRadius: BorderRadius.circular(50)),
                    child: state.deviceClasses[state.deviceTypes[device.device_type_id]?.device_class_id]?.imageWidget,
                  ),
                  title: Text(
                    state.deviceClasses[state.deviceTypes[device.device_type_id]?.device_class_id]?.name ?? "MISSING_DEVICE_CLASS_NAME",
                  ),
                  subtitle: Text(
                    state.deviceTypes[device.device_type_id]?.name ?? "MISSING_DEVICE_TYPE_NAME",
                  ),
                  trailing: Row(children: trailingHeader, mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.end),
                ),
                Container(
                  padding: const EdgeInsets.only(left: 6, right: 6),
                  child: const Divider(thickness: 2),
                ),
                ...widgets.skip(1), // skip first divider
              ],
            ),
          ),
        ),
      );
    });
  }
}
