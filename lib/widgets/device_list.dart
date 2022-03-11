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
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/config/function_config.dart';
import 'package:mobile_app/models/device_class.dart';
import 'package:mobile_app/models/device_command_response.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/services/device_commands.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/app_bar.dart';
import 'package:mobile_app/widgets/device_page.dart';
import 'package:mobile_app/widgets/toast.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';

class DeviceList extends StatefulWidget {
  const DeviceList({Key? key}) : super(key: key);

  @override
  State<DeviceList> createState() => _DeviceListState();
}

class _DeviceListState extends State<DeviceList> {
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  late final MyAppBar _appBar;
  late AppState _state;
  String _searchText = "";
  Timer? _searchDebounce;

  _DeviceListState() {
    _appBar = MyAppBar();
    _appBar.setTitle("Devices");
  }

  _searchChanged(String search) {
    _searchText = search;
    if (_searchDebounce?.isActive ?? false) _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _state.searchDevices(search, context);
    });
  }

  DeviceClass? _indexNeedsDeviceClassDivider(int i) {
    if (i > _state.devices.length - 1) {
      return null; // device not loaded yet
    }
    final deviceClassId = _state.deviceTypesPermSearch[_state.devices[i].device_type_id]?.device_class_id;
    if (i == 0 || deviceClassId != _state.deviceTypesPermSearch[_state.devices[i - 1].device_type_id]?.device_class_id) {
      return _state.deviceClasses[deviceClassId];
    }
    return null;
  }

  Widget _buildListWidget(String query) {
    _searchChanged(query);
    return RefreshIndicator(
      onRefresh: () => _state.refreshDevices(context),
      child: Scrollbar(
        child: _state.totalDevices == 0
            ? const Center(child: Text("No devices"))
            : _state.totalDevices == -1
                ? Center(child: PlatformCircularProgressIndicator())
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16.0),
                    itemCount: _state.totalDevices,
                    itemBuilder: (context, i) {
                      if (i >= _state.devices.length) {
                        _state.loadDevices(context);
                      }
                      final DeviceClass? c = _indexNeedsDeviceClassDivider(i);
                      List<Widget> columnWidgets = [const Divider()];
                      if (c != null) {
                        columnWidgets.add(ListTile(
                          title: Text(
                            c.name,
                            style: const TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                          ),
                        ));
                        columnWidgets.add(const Divider());
                      }
                      if (i > _state.devices.length - 1) {
                        return const SizedBox.shrink();
                      }
                      final List<Widget> trailingWidgets = [];
                      _state.devices[i].states
                          .where((element) => !element.isControlling && element.functionId == dotenv.env['FUNCTION_GET_ON_OFF_STATE'])
                          .forEach((element) {
                        trailingWidgets.add(Container(
                          width: MediaQuery.of(context).textScaleFactor * 50,
                          margin: EdgeInsets.only(left: MediaQuery.of(context).textScaleFactor * 4),
                          decoration: element.transitioning || element.value == null
                              ? null
                              : BoxDecoration(
                                  border: Border.all(color: Colors.grey),
                                  borderRadius: BorderRadius.circular(10),
                                  color: _state.devices[i].getConnectionStatus() == DeviceConnectionStatus.online ? null : Colors.grey,
                                ),
                          child: element.transitioning || element.value == null
                              ? Center(child: PlatformCircularProgressIndicator())
                              : IconButton(
                                  splashRadius: 25,
                                  tooltip: _state
                                      .nestedFunctions[
                                          functionConfigs[dotenv.env['FUNCTION_GET_ON_OFF_STATE']]?.getRelatedControllingFunction!(element.value)]
                                      ?.display_name,
                                  icon: functionConfigs[dotenv.env['FUNCTION_GET_ON_OFF_STATE']]?.getIcon(element.value) ??
                                      const Icon(Icons.help_outline),
                                  onPressed: () async {
                                    if (_state.devices[i].getConnectionStatus() != DeviceConnectionStatus.online) {
                                      Toast.showWarningToast(context, "Device not online", const Duration(milliseconds: 750));
                                      return;
                                    }
                                    if (element.transitioning) {
                                      return; // avoid double presses
                                    }
                                    final controllingFunction =
                                        functionConfigs[dotenv.env['FUNCTION_GET_ON_OFF_STATE']]?.getRelatedControllingFunction!(element.value);
                                    if (controllingFunction == null) {
                                      const err = "Could not find related controlling function";
                                      Toast.showErrorToast(context, err);
                                      _logger.e(err);
                                      return;
                                    }
                                    final controllingStates = _state.devices[i].states.where((state) =>
                                        state.isControlling &&
                                        state.functionId == controllingFunction &&
                                        state.serviceGroupKey == element.serviceGroupKey);
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
                                    _state.notifyListeners();
                                    final List<DeviceCommandResponse> responses = [];
                                    if (!await DeviceCommandsService.runCommandsSecurely(
                                        context, _state, [controllingStates.first.toCommand(_state.devices[i].id)], responses)) {
                                      element.transitioning = false;
                                      _state.notifyListeners();
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
                                    if (!await DeviceCommandsService.runCommandsSecurely(
                                        context, _state, [element.toCommand(_state.devices[i].id)], responses)) {
                                      element.transitioning = false;
                                      _state.notifyListeners();
                                      return;
                                    }
                                    assert(responses.length == 1);
                                    if (responses[0].status_code != 200) {
                                      final err = "Error running command: " + responses[0].message.toString();
                                      Toast.showErrorToast(context, err);
                                      element.transitioning = false;
                                      _state.notifyListeners();
                                      _logger.e(err);
                                      return;
                                    }
                                    element.value = responses[0].message[0];
                                    element.transitioning = false;
                                    _state.notifyListeners();
                                  },
                                ),
                        ));
                      });

                      final connectionStatus = _state.devices[i].getConnectionStatus();
                      columnWidgets.add(ListTile(
                        leading: connectionStatus == DeviceConnectionStatus.online
                            ? null
                            : Tooltip(
                                message: connectionStatus == DeviceConnectionStatus.offline
                                    ? "Device is offline"
                                    : (connectionStatus == DeviceConnectionStatus.unknown ? "Device status unknown" : ""),
                                child: connectionStatus == DeviceConnectionStatus.online
                                    ? null
                                    : Icon(PlatformIcons(context).error, color: MyTheme.warnColor)),
                        title: Text(_state.devices[i].name),
                        trailing: trailingWidgets.isEmpty
                            ? null
                            : Row(
                                children: trailingWidgets,
                                mainAxisSize: MainAxisSize.min, // limit size to needed
                              ),
                        onTap: () => Navigator.push(
                            context,
                            platformPageRoute(
                              context: context,
                              builder: (context) => DevicePage(i),
                            )),
                      ));
                      return Column(
                        children: columnWidgets,
                      );
                    }),
      ),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        _state = state;
        if (state.devices.isEmpty) {
          state.loadDevices(context);
        }

        List<Widget> actions = [
          PlatformWidget(
            material: (context, __) => PlatformIconButton(
                icon: Icon(PlatformIcons(context).search),
                onPressed: () {
                  showSearch(
                    context: context,
                    delegate: DevicesSearchDelegate(
                      _buildListWidget,
                      () {
                        _searchDebounce?.cancel();
                        _searchChanged("");
                      },
                      _searchChanged,
                    ),
                  );
                }),
            cupertino: (_, __) => const SizedBox.shrink(),
          ),
        ];

        if (kIsWeb) {
          actions.add(PlatformIconButton(
            onPressed: () => _state.refreshDevices(context),
            icon: const Icon(Icons.refresh),
            cupertino: (_, __) => CupertinoIconButtonData(padding: EdgeInsets.zero),
          ));
        }

        actions.addAll(MyAppBar.getDefaultActions(context));

        return PlatformScaffold(
          appBar: _appBar.getAppBar(context, actions),
          body: Column(children: [
            PlatformWidget(
                cupertino: (_, __) => Container(
                      child: CupertinoSearchTextField(
                          onChanged: (query) => _searchChanged(query), style: const TextStyle(color: Colors.black), itemColor: Colors.black),
                      padding: const EdgeInsets.all(16.0),
                    ),
                material: (_, __) => const SizedBox.shrink()),
            Expanded(
              child: _buildListWidget(_searchText),
            ),
          ]),
        );
      },
    );
  }
}

class DevicesSearchDelegate extends SearchDelegate {
  final Widget Function(String query) _resultBuilder;
  final void Function() _onReturn;
  final void Function(String query) _onChanged;
  late final Consumer<AppState> _consumer;

  DevicesSearchDelegate(this._resultBuilder, this._onReturn, this._onChanged) {
    _consumer = Consumer<AppState>(builder: (state, __, ___) {
      return _resultBuilder(query);
    });
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return MyAppBar.getDefaultActions(context);
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
        onPressed: () {
          _onReturn();
          close(context, null);
        },
        icon: const Icon(Icons.arrow_back));
  }

  @override
  Widget buildResults(BuildContext context) {
    _onChanged(query);
    return _consumer;
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    _onChanged(query);
    return _consumer;
  }

  @override
  ThemeData appBarTheme(BuildContext context) {
    return MyTheme.materialTheme;
  }
}
