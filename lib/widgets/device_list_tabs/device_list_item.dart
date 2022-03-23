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

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../config/function_config.dart';
import '../../models/device_command_response.dart';
import '../../models/device_instance.dart';
import '../../services/device_commands.dart';
import '../../theme.dart';
import '../device_page.dart';
import '../toast.dart';

class DeviceListItem extends StatelessWidget {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  final int _stateDeviceIndex;
  final FutureOr<dynamic> Function(dynamic)? _poppedCallback;

  const DeviceListItem(this._stateDeviceIndex, this._poppedCallback, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, child) {
      final device = state.devices[_stateDeviceIndex];
      final List<Widget> trailingWidgets = [];
      device.states.where((element) => !element.isControlling && element.functionId == dotenv.env['FUNCTION_GET_ON_OFF_STATE']).forEach((element) {
        trailingWidgets.add(Container(
          width: MediaQuery.of(context).textScaleFactor * 50,
          margin: EdgeInsets.only(left: MediaQuery.of(context).textScaleFactor * 4),
          child: element.transitioning || element.value == null
              ? Center(child: PlatformCircularProgressIndicator())
              : IconButton(
                  splashRadius: 25,
                  tooltip: state
                      .nestedFunctions[functionConfigs[dotenv.env['FUNCTION_GET_ON_OFF_STATE']]?.getRelatedControllingFunction(element.value)]
                      ?.display_name,
                  icon: functionConfigs[dotenv.env['FUNCTION_GET_ON_OFF_STATE']]?.getIcon(element.value) ?? const Icon(Icons.help_outline),
                  onPressed: device.getConnectionStatus() == DeviceConnectionStatus.offline
                      ? null
                      : () async {
                          if (device.getConnectionStatus() == DeviceConnectionStatus.offline) {
                            Toast.showWarningToast(context, "Device is offline", const Duration(milliseconds: 750));
                            return;
                          }
                          if (element.transitioning) {
                            return; // avoid double presses
                          }
                          final controllingFunction =
                              functionConfigs[dotenv.env['FUNCTION_GET_ON_OFF_STATE']]?.getRelatedControllingFunction(element.value);
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
                          element.transitioning = true;
                          state.notifyListeners();
                          final List<DeviceCommandResponse> responses = [];
                          if (!await DeviceCommandsService.runCommandsSecurely(
                              context, state, [controllingStates.first.toCommand(device.id)], responses)) {
                            element.transitioning = false;
                            state.notifyListeners();
                            return;
                          }
                          assert(responses.length == 1);
                          if (responses[0].status_code != 200) {
                            final err = "Error running command: " + responses[0].message.toString();
                            Toast.showErrorToast(context, err);
                            _logger.e(err);
                            return;
                          }
                          responses.clear();
                          if (!await DeviceCommandsService.runCommandsSecurely(context, state, [element.toCommand(device.id)], responses)) {
                            element.transitioning = false;
                            state.notifyListeners();
                            return;
                          }
                          assert(responses.length == 1);
                          if (responses[0].status_code != 200) {
                            final err = "Error running command: " + responses[0].message.toString();
                            Toast.showErrorToast(context, err);
                            element.transitioning = false;
                            state.notifyListeners();
                            _logger.e(err);
                            return;
                          }
                          element.value = responses[0].message[0];
                          element.transitioning = false;
                          state.notifyListeners();
                        },
                ),
        ));
      });

      final connectionStatus = device.getConnectionStatus();
      final List<Widget> columnWidgets = [];
      columnWidgets.add(ListTile(
        leading: connectionStatus == DeviceConnectionStatus.offline
            ? Tooltip(
                message: "Device is offline",
                child: connectionStatus == DeviceConnectionStatus.offline ? Icon(PlatformIcons(context).error, color: MyTheme.warnColor) : null)
            : null,
        title: Text(device.name),
        trailing: trailingWidgets.isEmpty
            ? null
            : Row(
                children: trailingWidgets,
                mainAxisSize: MainAxisSize.min, // limit size to needed
              ),
        onTap: () {
          final future = Navigator.push(
              context,
              platformPageRoute(
                context: context,
                builder: (context) {
                  final target = DevicePage(_stateDeviceIndex, null);
                  target.refresh(context, state);
                  return target;
                },
              ));
          if (_poppedCallback != null) {
            future.then(_poppedCallback!);
          }
        },
      ));
      return Column(
        children: columnWidgets,
        mainAxisSize: MainAxisSize.min,
      );
    });
  }
}
