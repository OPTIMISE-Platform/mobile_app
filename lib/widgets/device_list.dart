import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:mobile_app/models/device_class.dart';
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

  String getDeviceTitle(int index) {
    if (_state.devices.length > index) {
      return _state.devices[index].name;
    } else {
      return "";
    }
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
    final deviceClassId =
        _state.deviceTypes[_state.devices[i].device_type_id]?.device_class_id;
    if (i == 0 ||
        deviceClassId !=
            _state.deviceTypes[_state.devices[i - 1].device_type_id]
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
                      trailing: Container(
                        height: MediaQuery.of(context).textScaleFactor * 24,
                        width: MediaQuery.of(context).textScaleFactor * 24,
                        decoration: BoxDecoration(
                            color: const Color(0xFF6c6c6c),
                            borderRadius: BorderRadius.circular(50)),
                        child: c.imageWidget,
                      ),
                      title: Text(
                        c.name,
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ));
                    columnWidgets.add(const Divider());
                  }
                  columnWidgets.add(ListTile(
                    title: Container(
                        padding: EdgeInsets.only(
                            left: MediaQuery.of(context).textScaleFactor * 24),
                        child: Text(getDeviceTitle(i))),
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
            onPressed: () async => _searchChanged(_searchText),
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
