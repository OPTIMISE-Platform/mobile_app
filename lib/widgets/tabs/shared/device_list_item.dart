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

import 'package:badges/badges.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:logger/logger.dart';
import 'package:provider/provider.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../../../app_state.dart';
import '../../../config/function_config.dart';
import '../../../models/device_command_response.dart';
import '../../../models/device_instance.dart';
import '../../../services/device_commands.dart';
import '../../../services/settings.dart';
import '../../../theme.dart';
import '../../shared/favorize_button.dart';
import '../../shared/toast.dart';
import 'detail_page/detail_page.dart';

class DeviceListItem extends StatelessWidget {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  final int _stateDeviceIndex;
  final FutureOr<dynamic> Function(dynamic)? _poppedCallback;
  final GlobalKey _keyFavButton = GlobalKey();
  FavorizeButton? _favorizeButton;

  DeviceListItem(this._stateDeviceIndex, this._poppedCallback, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, child) {
      final device = state.devices[_stateDeviceIndex];
      final List<Widget> trailingWidgets = [];
      device.states.where((element) => !element.isControlling && element.functionId == dotenv.env['FUNCTION_GET_ON_OFF_STATE']).forEach((element) {
        trailingWidgets.add(Container(
          width: MediaQuery.of(context).textScaleFactor * 50,
          margin: EdgeInsets.only(left: MediaQuery.of(context).textScaleFactor * 4),
          child: element.transitioning
              ? Center(child: PlatformCircularProgressIndicator())
              : element.value == null
                  ? Center(
                      child: Tooltip(
                          message: "Status unknown",
                          triggerMode: TooltipTriggerMode.tap,
                          child: Icon(
                            PlatformIcons(context).remove,
                          )))
                  : PlatformIconButton(
                      cupertino: (_, __) => CupertinoIconButtonData(padding: EdgeInsets.zero),
                      material: (_, __) => MaterialIconButtonData(
                          splashRadius: 25,
                          tooltip: state
                              .nestedFunctions[functionConfigs[dotenv.env['FUNCTION_GET_ON_OFF_STATE']]?.getRelatedControllingFunction(element.value)]
                              ?.display_name),
                      icon: functionConfigs[dotenv.env['FUNCTION_GET_ON_OFF_STATE']]?.displayValue(element.value, context) ??
                          const Icon(Icons.help_outline),
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
                              if (!await DeviceCommandsService.runCommandsSecurely(context, [controllingStates.first.toCommand()], responses)) {
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
                              if (!await DeviceCommandsService.runCommandsSecurely(context, [element.toCommand()], responses, false)) {
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
        title: Container(
            alignment: Alignment.centerLeft,
            child: Badge(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: MyTheme.insetSize),
              position: BadgePosition.topEnd(),
              child: Text(
                device.displayName,
              ),
              badgeContent: Icon(PlatformIcons(context).error, size: 16, color: MyTheme.warnColor),
              showBadge: connectionStatus == DeviceConnectionStatus.offline,
              badgeColor: Colors.transparent,
              elevation: 0,
            )),
        trailing: trailingWidgets.isEmpty
            ? _favorizeButton = FavorizeButton(_stateDeviceIndex, null, key: _keyFavButton)
            : Row(
                children: [
                  ...trailingWidgets,
                  const VerticalDivider(),
                  _favorizeButton = FavorizeButton(_stateDeviceIndex, null, key: _keyFavButton)
                ],
                mainAxisSize: MainAxisSize.min, // limit size to needed
              ),
        onTap: () {
          final future = Navigator.push(
              context,
              platformPageRoute(
                context: context,
                builder: (context) {
                  final target = DetailPage(_stateDeviceIndex, null);
                  return target;
                },
              ));
          if (_poppedCallback != null) {
            future.then(_poppedCallback!);
          }
        },
      ));
      WidgetsBinding.instance?.addPostFrameCallback((_) => _showTutorial(context));
      return Column(
        children: columnWidgets,
        mainAxisSize: MainAxisSize.min,
      );
    });
  }

  void _showTutorial(BuildContext context) {
    if (!Settings.tutorialSeen(Tutorial.deviceListItem)) {
      TutorialCoachMark(
        context,
        targets: [
          TargetFocus(keyTarget: _keyFavButton, contents: [
            TargetContent(
                align: ContentAlign.bottom,
                child: const Text(
                  "Toggle favorite",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24),
                ),
                padding: const EdgeInsets.only(top: 50))
          ]),
        ],
        colorShadow: MyTheme.appColor,
        onClickTarget: (focus) {
          _favorizeButton!.click();
        },
        alignSkip: Alignment.topRight,
      ).show();
      Settings.markTutorialSeen(Tutorial.deviceListItem);
    }
  }
}
