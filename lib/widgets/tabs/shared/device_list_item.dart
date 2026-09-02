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

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logger/logger.dart';

import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/config/functions/function_config.dart';
import 'package:mobile_app/models/device_command_response.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/services/device_commands.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/shared/favorize_button.dart';
import 'package:mobile_app/widgets/shared/toast.dart';
import 'package:mobile_app/widgets/tabs/shared/detail_page/detail_page.dart';

class DeviceListItem extends StatefulWidget {
  final DeviceInstance _device;
  final FutureOr<dynamic> Function(dynamic)? _poppedCallback;
  final GlobalKey _keyFavButton = GlobalKey();

  DeviceListItem(this._device, this._poppedCallback, {Key? key})
      : super(key: key);

  @override
  State<StatefulWidget> createState() => _DeviceListItemState();
}

class _DeviceListItemState extends State<DeviceListItem> {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  // Lives on the State, where it survives widget rebuilds by itself. On the
  // widget it needed a didUpdateWidget copy to carry it across, and made the
  // widget mutable.
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
        listenable: widget._device.stateNotifier,
        builder: (context, child) {
      final device = widget._device;
      final List<Widget> trailingWidgets = [];
      final filteredStates = device.states.where((element) =>
          !element.isControlling &&
          element.functionId == dotenv.env['FUNCTION_GET_ON_OFF_STATE']);
      filteredStates.forEach((element) {
        trailingWidgets.add(Container(
          width: MediaQuery.of(context).textScaleFactor * 50,
          margin:
              EdgeInsets.only(left: MediaQuery.of(context).textScaleFactor * 4),
          child: element.transitioning
              ? const Center(child: DelayedCircularProgressIndicator())
              : element.value == null
                  ? Center(
                      child: Tooltip(
                          message: "Status unknown",
                          triggerMode: TooltipTriggerMode.tap,
                          child: Icon(
                            Icons.remove,
                          )))
                  : IconButton(
                      splashRadius: 25,
                      tooltip: AppState()
                          .platformFunctions[functionConfigs[
                                  dotenv.env['FUNCTION_GET_ON_OFF_STATE']]
                              ?.getRelatedControllingFunction(element.value)]
                          ?.display_name,
                      icon: functionConfigs[
                                  dotenv.env['FUNCTION_GET_ON_OFF_STATE']]
                              ?.displayValue(element.value, context) ??
                          const Icon(Icons.help_outline),
                      onPressed: device.connection_state ==
                              DeviceConnectionStatus.offline
                          ? null
                          : () async {
                              if (device.connection_state ==
                                  DeviceConnectionStatus.offline) {
                                Toast.showToastNoContext("Device is offline");
                                return;
                              }
                              if (element.transitioning) {
                                return; // avoid double presses
                              }
                              final controllingFunction = functionConfigs[
                                      dotenv.env['FUNCTION_GET_ON_OFF_STATE']]
                                  ?.getRelatedControllingFunction(
                                      element.value);
                              if (controllingFunction == null) {
                                const err =
                                    "Could not find related controlling function";
                                Toast.showToastNoContext(err);
                                _logger.e(err);
                                return;
                              }
                              final controllingStates = device.states.where(
                                  (state) =>
                                      state.isControlling &&
                                      state.functionId == controllingFunction &&
                                      state.serviceGroupKey ==
                                          element.serviceGroupKey &&
                                      state.aspectId == element.aspectId);
                              if (controllingStates.isEmpty) {
                                const err =
                                    "Found no controlling service, check device type!";
                                Toast.showToastNoContext(err);
                                _logger.e(err);
                                return;
                              }
                              if (controllingStates.length > 1) {
                                const err =
                                    "Found more than one controlling service, check device type!";
                                Toast.showToastNoContext(err);
                                _logger.e(err);
                                return;
                              }
                              element.transitioning = true;
                              widget._device.notifyStateChanged();
                              final List<DeviceCommandResponse> responses = [];
                              if (!await DeviceCommandsService
                                  .runCommandsSecurely(
                                      [controllingStates.first.toCommand()],
                                      responses)) {
                                element.transitioning = false;
                                widget._device.notifyStateChanged();
                                return;
                              }
                              assert(responses.length == 1);
                              if (responses[0].status_code != 200) {
                                final err =
                                    "Error running command: ${responses[0].message}";
                                Toast.showToastNoContext(err);
                                _logger.e(err);
                                return;
                              }
                              responses.clear();
                              if (!await DeviceCommandsService
                                  .runCommandsSecurely(
                                      [element.toCommand()],
                                      responses,
                                      false)) {
                                element.transitioning = false;
                                widget._device.notifyStateChanged();
                                return;
                              }
                              assert(responses.length == 1);
                              if (responses[0].status_code != 200) {
                                final err =
                                    "Error running command: ${responses[0].message}";
                                Toast.showToastNoContext(err);
                                element.transitioning = false;
                                widget._device.notifyStateChanged();
                                _logger.e(err);
                                return;
                              }
                              element.value = responses[0].message[0];
                              element.transitioning = false;
                              widget._device.notifyStateChanged();
                            },
                    ),
        ));
      });

      final connectionStatus = device.connection_state;
      final unavailable = connectionStatus == DeviceConnectionStatus.offline ||
          device.network?.localService == null && Settings.getLocalMode();
      final List<Widget> columnWidgets = [];
      columnWidgets.add(ListTile(
        title: Text(device.displayName),
        leading: FavorizeButton(device, null, key: widget._keyFavButton),
        trailing: unavailable
            ? IconButton(
                onPressed: null,
                icon: Icon(
                    connectionStatus == DeviceConnectionStatus.offline
                        ? Icons.error
                        : Icons.lan_outlined,
                    color: MyTheme.warnColor))
            : trailingWidgets.isEmpty
                ? null
                : trailingWidgets.length == 1
                    ? trailingWidgets[0]
                    : IconButton(
                        splashRadius: 25,
                        icon: Icon(
                            _expanded ? Icons.expand_less : Icons.expand_more),
                        onPressed: () => setState(() => _expanded = !_expanded)),
        onTap: () => _onTap(context),
      ));

      if (_expanded) {
        columnWidgets.add(
          ListTile(
              title: Wrap(
            alignment: WrapAlignment.spaceEvenly,
            children: trailingWidgets,
          )),
        );
      }

      return AnimatedSize(
          duration: const Duration(milliseconds: 75),
          alignment: Alignment.topLeft,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: columnWidgets,
          ));
    });
  }

  _onTap(BuildContext context) {
    final future = Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) {
            final target = DetailPage(widget._device, null);
            return target;
          },
        ));
    if (widget._poppedCallback != null) {
      future.then(widget._poppedCallback!);
    }
  }
}
