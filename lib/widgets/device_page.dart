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

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/config/function_config.dart';
import 'package:mobile_app/widgets/app_bar.dart';
import 'package:mobile_app/widgets/toast.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/device_command_response.dart';
import '../models/device_instance.dart';
import '../services/device_commands.dart';
import '../theme.dart';

class DevicePage extends StatefulWidget {
  final int _stateDeviceIndex;

  const DevicePage(this._stateDeviceIndex, {Key? key}) : super(key: key);

  @override
  State<DevicePage> createState() => _DevicePageState(_stateDeviceIndex);
}

class _DevicePageState extends State<DevicePage> {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  final int _stateDeviceIndex;

  late final MyAppBar _appBar;
  late AppState _state;
  bool _initialized = false;

  _DevicePageState(this._stateDeviceIndex) {
    _appBar = MyAppBar();
    _appBar.setTitle("Device Page");
    _logger.d("Device Page opened for index " + _stateDeviceIndex.toString());
  }

  _refresh(context) async {
    for (var element in _state.devices[_stateDeviceIndex].states) {
      if (!element.isControlling) {
        element.value = null;
        element.transitioning = true;
      }
    }
    if (_initialized) _state.notifyListeners();
    _state.loadStates(context, [_state.devices[_stateDeviceIndex]]);
    _initialized = true;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        _state = state;
        if (!_initialized) {
          _refresh(context);
        }
        final device = _state.devices[_stateDeviceIndex];
        final connectionStatus = device.getConnectionStatus();
        _appBar.setTitle(device.name);
        if (state.devices.isEmpty) {
          state.loadDevices(context);
        }
        List<Widget> appBarActions = [];

        if (kIsWeb) {
          appBarActions.add(PlatformIconButton(
            onPressed: () => _refresh(context),
            icon: const Icon(Icons.refresh),
            cupertino: (_, __) => CupertinoIconButtonData(padding: EdgeInsets.zero),
          ));
        }
        appBarActions.addAll(MyAppBar.getDefaultActions(context));

        List<Widget> actionWidgets = [];
        actionWidgets.add(Container(
          padding: const EdgeInsets.only(left: 6, right: 6),
          child: const Divider(thickness: 2),
        ));
        actionWidgets.add(const ListTile(title: Text("Actions", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))));

        List<Widget> statusWidgets = [];
        statusWidgets.add(const Divider(thickness: 2));
        statusWidgets.add(const ListTile(title: Text("Status", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))));

        for (var element in device.states) {
          final function = _state.nestedFunctions[element.functionId];
          var functionConfig = functionConfigs[element.functionId];

          String title = function?.display_name ?? "MISSING_FUNCTION_NAME";
          if (title.isEmpty) title = function?.name ?? "MISSING_FUNCTION_NAME";

          if (element.isControlling) {
            actionWidgets.add(Column(children: [
              const Divider(),
              ListTile(
                title: Text(title),
                trailing: Container(
                  width: MediaQuery.of(context).textScaleFactor * 50,
                  margin: EdgeInsets.only(left: MediaQuery.of(context).textScaleFactor * 4),
                  decoration: element.transitioning
                      ? null
                      : BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(10),
                          color: connectionStatus == DeviceConnectionStatus.online ? null : Colors.grey,
                        ),
                  child: element.transitioning
                      ? Center(child: PlatformCircularProgressIndicator())
                      : IconButton(
                          splashRadius: 25,
                          icon: functionConfig?.getIcon(element.value) ?? const Icon(Icons.input),
                          onPressed: () async {
                            if (connectionStatus != DeviceConnectionStatus.online) {
                              Toast.showWarningToast(context, "Device not online", const Duration(milliseconds: 750));
                              return;
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
                              measuringFunctionConfig ??= FunctionConfigDefault(_state, device.states[i].functionId);
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
                              functionConfig ??= FunctionConfigDefault(_state, element.functionId);
                              Widget? content = functionConfig!.build(context, transitioningStates.length == 1 ? device.states[transitioningStates[0]].value : null);
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
                                    PlatformDialogAction(
                                        child: PlatformText('OK'), onPressed: () => Navigator.pop(context, functionConfig!.getConfiguredValue())),
                                  ],
                                ),
                              );
                              if (input == null) {
                                return; // canceled
                              }
                            }
                            functionConfig = null; // ensure early release and no reuse
                            element.transitioning = true;
                            _state.notifyListeners();
                            final List<DeviceCommandResponse> responses = [];
                            if (!await DeviceCommandsService.runCommandsSecurely(context, _state, [element.toCommand(device.id, input)], responses)) {
                              element.transitioning = false;
                              _state.notifyListeners();
                              return;
                            }
                            assert(responses.length == 1);
                            if (responses[0].status_code != 200) {
                              element.transitioning = false;
                              _state.notifyListeners();
                              const err = "Error running command";
                              Toast.showErrorToast(context, err);
                              _logger.e(err + ": " + responses[0].message.toString());
                              return;
                            }
                            element.transitioning = false;
                            _state.notifyListeners();

                            // refresh changed measurements
                            for (var i in transitioningStates) {
                              device.states[i].transitioning = true;
                            }
                            _state.notifyListeners();
                            responses.clear();
                            if (!await DeviceCommandsService.runCommandsSecurely(
                                context, state, commandCallbacks.map((e) => e.command).toList(growable: false), responses)) {
                              for (var i in transitioningStates) {
                                device.states[i].transitioning = false;
                              }
                              _state.notifyListeners();
                              return;
                            }
                            assert(responses.length == commandCallbacks.length);
                            for (var i = 0; i < responses.length; i++) {
                              commandCallbacks[i].callback(responses[i]);
                            }
                            _state.notifyListeners();
                          },
                        ),
                ),
              ),
            ]));
          } else {
            statusWidgets.add(Column(children: [
              const Divider(),
              ListTile(
                title: Text(title),
                trailing: element.transitioning
                    ? PlatformCircularProgressIndicator()
                    : functionConfigs.containsKey(element.functionId)
                        ? functionConfigs[element.functionId]!.displayValue(element.value)
                        : Text(element.value.toString() +
                            " " +
                            (_state.nestedFunctions[element.functionId]?.concept.base_characteristic?.display_unit ?? "")),
              ),
            ]));
          }
        }

        return PlatformScaffold(
          appBar: _appBar.getAppBar(context, appBarActions),
          body: RefreshIndicator(
            onRefresh: () => _refresh(context),
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
                      child: _state.deviceClasses[_state.deviceTypes[device.device_type_id]?.device_class_id]?.imageWidget,
                    ),
                    title: Text(
                      _state.deviceClasses[_state.deviceTypes[device.device_type_id]?.device_class_id]?.name ?? "MISSING_DEVICE_CLASS_NAME",
                    ),
                    subtitle: Text(
                      _state.deviceTypes[device.device_type_id]?.name ?? "MISSING_DEVICE_TYPE_NAME",
                    ),
                    trailing: connectionStatus == DeviceConnectionStatus.online
                        ? null
                        : Tooltip(
                            message: connectionStatus == DeviceConnectionStatus.offline
                                ? "Device is offline"
                                : (connectionStatus == DeviceConnectionStatus.unknown ? "Device status unknown" : ""),
                            child: connectionStatus == DeviceConnectionStatus.online
                                ? null
                                : Icon(PlatformIcons(context).error, color: MyTheme.warnColor)),
                  ),
                  ...actionWidgets,
                  ...statusWidgets,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
