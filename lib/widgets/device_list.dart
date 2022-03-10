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
import 'package:mobile_app/models/device_class.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/app_bar.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';

class DeviceList extends StatefulWidget {
  const DeviceList({Key? key}) : super(key: key);

  @override
  State<DeviceList> createState() => _DeviceListState();
}

class _DeviceListState extends State<DeviceList> {
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
    final deviceClassId = _state
        .deviceTypesPermSearch[_state.devices[i].device_type_id]
        ?.device_class_id;
    if (i == 0 ||
        deviceClassId !=
            _state.deviceTypesPermSearch[_state.devices[i - 1].device_type_id]
                ?.device_class_id) {
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
                          /*
                          trailing: Container(
                            height: MediaQuery.of(context).textScaleFactor * 24,
                            width: MediaQuery.of(context).textScaleFactor * 24,
                            decoration: BoxDecoration(
                                color: const Color(0xFF6c6c6c),
                                borderRadius: BorderRadius.circular(50)),
                            child: c.imageWidget,
                          ),
                           */
                          title: Text(
                            c.name,
                            style: const TextStyle(
                                color: Colors.grey,
                                fontStyle: FontStyle.italic),
                          ),
                        ));
                        columnWidgets.add(const Divider());
                      }
                      if (i > _state.devices.length - 1) {
                        return const SizedBox.shrink();
                      }
                      final List<Widget> onOffButtons = [];
                      _state.devices[i].states
                          .where((element) =>
                              !element.isControlling &&
                              element.functionId ==
                                  dotenv.env['FUNCTION_GET_ON_OFF_STATE'])
                          .forEach((element) {
                        onOffButtons.add(Container(
                          margin: EdgeInsets.only(left: MediaQuery.of(context).textScaleFactor * 4),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey, width: 1),
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: IconButton(
                            icon: Icon(element.value == true
                                ? Icons.power_outlined
                                : Icons.power_off_outlined),
                            onPressed: () {
                              // TODO
                            },
                          ),
                        ));
                      });

                      final connectionStatus =
                          _state.devices[i].getConnectionStatus();
                      columnWidgets.add(ListTile(
                        leading: Icon(connectionStatus ==
                                DeviceConnectionStatus.online
                            ? PlatformIcons(context).checkMarkCircledOutline
                            : connectionStatus == DeviceConnectionStatus.offline
                                ? PlatformIcons(context).clearThickCircled
                                : PlatformIcons(context).helpOutline),
                        title: Text(_state.devices[i].name),
                        trailing: onOffButtons.isEmpty
                            ? null
                            : Row(
                                children: onOffButtons,
                                mainAxisSize:
                                    MainAxisSize.min, // limit size to needed
                              ),
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
            cupertino: (_, __) =>
                CupertinoIconButtonData(padding: EdgeInsets.zero),
          ));
        }

        actions.addAll(MyAppBar.getDefaultActions(context));

        return PlatformScaffold(
          appBar: _appBar.getAppBar(context, actions),
          body: Column(children: [
            PlatformWidget(
                cupertino: (_, __) => Container(
                      child: CupertinoSearchTextField(
                          onChanged: (query) => _searchChanged(query),
                          style: const TextStyle(color: Colors.black),
                          itemColor: Colors.black),
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
