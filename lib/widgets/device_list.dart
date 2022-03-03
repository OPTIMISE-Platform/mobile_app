import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/models/device_permsearch.dart';
import 'package:mobile_app/services/devices.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/app_bar.dart';
import 'package:mobile_app/widgets/toast.dart';

class DeviceList extends StatefulWidget {
  DeviceList({Key? key}) : super(key: key) {}

  @override
  State<DeviceList> createState() => _DeviceListState();
}

class _DeviceListState extends State<DeviceList> {
  late final MyAppBar _appBar;
  List<DevicePermSearch> _devices = <DevicePermSearch>[];
  int _offset = 0;
  int _totalDevices = 0;
  Timer? _searchDebounce;
  String _searchText = '';
  static final _logger = Logger(
    printer: SimplePrinter(),
  );

  _DeviceListState() {
    _appBar = MyAppBar();
    _appBar.setTitle("Devices");
  }

  bool _mounted() {
    return mounted;
  }

  _loadMoreDevices(BuildContext context, StateSetter setState,
      bool Function() mounted) async {
    if (_totalDevices == 0) {
      try {
        _totalDevices =
            await DevicesService.getTotalDevices(context, _searchText);
      } catch (e) {
        _logger.e("Could not get total devices: " + e.toString());
      }
    }

    if (_devices.length < _offset) {
      // already loading
      return;
    }
    const pageSize = 100;
    _offset += pageSize;
    late final List<DevicePermSearch> newDevices;
    try {
      newDevices = await DevicesService.getDevices(
          context, pageSize, _offset - pageSize, _searchText, []);
    } catch (e) {
      _logger.e("Could not get devices: " + e.toString());
      Toast.showErrorToast(context, "Could not load devices");
      return;
    }
    if (mounted()) {
      _devices.addAll(newDevices);
      setState(() {});
    } else {
      _logger.d("Skipping setState, no longer mounted");
    }
  }

  String getDeviceTitle(int index) {
    if (_devices.length > index) {
      return _devices[index].name;
    } else {
      return "";
    }
  }

  _searchChanged(String search, StateSetter setState, bool Function() mounted) {
    if (_searchText == search) {
      return;
    }
    if (_searchDebounce?.isActive ?? false) _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _searchDevices(search, setState, mounted, false);
    });
  }

  _searchDevices(String search, StateSetter setState, bool Function() mounted,
      bool force) {
    if (_searchText == search && !force) {
      return;
    }
    _searchText = search;
    _offset = 0;
    _totalDevices = 0;
    _devices = [];
    _loadMoreDevices(context, setState, mounted);
  }

  Widget _buildListWidget(String query, bool Function() mounted) {
    return StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
      _searchChanged(query, setState, mounted);
      return RefreshIndicator(
        onRefresh: () async =>
            _searchDevices(_searchText, setState, mounted, true),
        child: Scrollbar(
          isAlwaysShown: true,
          child: _totalDevices == 0
              ? const Center(child: Text("No devices"))
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16.0),
                  itemCount: _totalDevices * 2,
                  itemBuilder: (context, i) {
                    if (i.isOdd) return const Divider();
                    final index = i ~/ 2;
                    if (index >= _devices.length) {
                      _loadMoreDevices(context, setState, mounted);
                    }
                    return ListTile(
                      title: Text(getDeviceTitle(index)),
                    );
                  }),
        ),
      );
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_devices.isEmpty) {
      _loadMoreDevices(context, setState, _mounted);
    }

    List<Widget> actions = [
      PlatformWidget(
        material: (_, __) => PlatformIconButton(
            icon: Icon(PlatformIcons(context).search),
            onPressed: () {
              showSearch(
                context: context,
                delegate: DevicesSearchDelegate(
                  _buildListWidget,
                  () {
                    _searchDebounce?.cancel();
                    _searchDevices("", setState, _mounted, false);
                  },
                ),
              );
            }),
        cupertino: (_, __) => const SizedBox.shrink(),
      ),
    ];

    if (kIsWeb) {
      actions.add(PlatformIconButton(
        onPressed: () async =>
            _searchDevices(_searchText, setState, () => mounted, true),
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
                      onChanged: (query) =>
                          _searchChanged(query, setState, _mounted),
                      style: const TextStyle(color: Colors.black),
                      itemColor: Colors.black),
                  padding: const EdgeInsets.all(16.0),
                ),
            material: (_, __) => const SizedBox.shrink()),
        Expanded(
          child: _buildListWidget(_searchText, _mounted),
        ),
      ]),
    );
  }
}

class DevicesSearchDelegate extends SearchDelegate {
  final Widget Function(String query, bool Function() mounted) _resultBuilder;
  final void Function() _onReturn;
  bool __closed = false;

  DevicesSearchDelegate(this._resultBuilder, this._onReturn);

  @override
  List<Widget>? buildActions(BuildContext context) {
    return MyAppBar.getDefaultActions(context);
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
        onPressed: () {
          __closed = true;
          _onReturn();
          close(context, null);
        },
        icon: const Icon(Icons.arrow_back));
  }

  @override
  Widget buildResults(BuildContext context) {
    return _resultBuilder(query, _mounted);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _resultBuilder(query, _mounted);
  }

  @override
  ThemeData appBarTheme(BuildContext context) {
    return MyTheme.materialTheme;
  }

  bool _mounted() {
    return !__closed;
  }
}
