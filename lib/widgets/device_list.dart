import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/models/device_class.dart';
import 'package:mobile_app/models/device_permsearch.dart';
import 'package:mobile_app/models/device_type.dart';
import 'package:mobile_app/services/device_classes.dart';
import 'package:mobile_app/services/device_types.dart';
import 'package:mobile_app/services/devices.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/app_bar.dart';
import 'package:mobile_app/widgets/toast.dart';
import 'package:mutex/mutex.dart';

class DeviceList extends StatefulWidget {
  const DeviceList({Key? key}) : super(key: key);

  @override
  State<DeviceList> createState() => _DeviceListState();
}

class _DeviceListState extends State<DeviceList> {
  late final MyAppBar _appBar;
  List<DevicePermSearch> _devices = <DevicePermSearch>[];
  int _totalDevices = 0;
  Timer? _searchDebounce;
  String _searchText = '';
  int _deviceClassArrIndex = 0;
  int _classOffset = 0;
  final _m = Mutex();
  static final _logger = Logger(
    printer: SimplePrinter(),
  );
  final Map<String, DeviceClass> _deviceClasses = {};
  final Map<String, DeviceTypePermSearch> _deviceTypes = {};

  _DeviceListState() {
    _appBar = MyAppBar();
    _appBar.setTitle("Devices");
  }

  bool _mounted() {
    return mounted;
  }

  _loadMoreDevices(
      BuildContext context, StateSetter setState, bool Function() mounted,
      [int size = 100]) async {
    // default page size = 100
    if (_m.isLocked) {
      return;
    }
    _m.acquire();
    _logger.d("Loading more devices");
    if (_deviceClasses.isEmpty) {
      for (var element
          in (await DeviceClassesService.getDeviceClasses(context))) {
        _deviceClasses[element.id] = element;
      }
    }
    if (_deviceTypes.isEmpty) {
      for (var element in (await DeviceTypesService.getDeviceTypes(context))) {
        _deviceTypes[element.id] = element;
      }
    }

    if (_totalDevices == 0) {
      try {
        _totalDevices =
            await DevicesService.getTotalDevices(context, _searchText);
      } catch (e) {
        _logger.e("Could not get total devices: " + e.toString());
      }
    }
    late final List<DevicePermSearch> newDevices;
    try {
      List<String> deviceTypeIds = _deviceTypes.values
          .where((element) =>
              element.device_class_id ==
              _deviceClasses.keys.elementAt(_deviceClassArrIndex))
          .map((e) => e.id)
          .toList(growable: false);

      newDevices = await DevicesService.getDevices(
          context, size, _classOffset, _searchText, deviceTypeIds);
    } catch (e) {
      _logger.e("Could not get devices: " + e.toString());
      Toast.showErrorToast(context, "Could not load devices");
      return;
    } finally {
      _m.release();
    }
    if (mounted()) {
      _devices.addAll(newDevices);
      _classOffset += newDevices.length;
      setState(() {});
      if (newDevices.length < size &&
          _deviceClasses.length - 1 > _deviceClassArrIndex) {
        _classOffset = 0;
        _deviceClassArrIndex++;
        _loadMoreDevices(context, setState, mounted, size - newDevices.length);
      }
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
    _classOffset = 0;
    _deviceClassArrIndex = 0;
    _totalDevices = 0;
    _devices = [];
    _loadMoreDevices(context, setState, mounted);
  }

  DeviceClass? _indexNeedsDeviceClassDivider(int i) {
    if (i > _devices.length - 1) {
      return null; // device not loaded yet
    }
    final deviceClassId =
        _deviceTypes[_devices[i].device_type_id]?.device_class_id;
    if (i == 0 ||
        deviceClassId !=
            _deviceTypes[_devices[i - 1].device_type_id]?.device_class_id) {
      return _deviceClasses[deviceClassId];
    }
    return null;
  }

  Widget _buildListWidget(String query, bool Function() mounted) {
    return StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
      _searchChanged(query, setState, mounted);
      return RefreshIndicator(
        onRefresh: () async =>
            _searchDevices(_searchText, setState, mounted, true),
        child: Scrollbar(
          child: _totalDevices == 0
              ? const Center(child: Text("No devices"))
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16.0),
                  itemCount: _totalDevices,
                  itemBuilder: (context, i) {
                    if (i >= _devices.length) {
                      _loadMoreDevices(context, setState, mounted);
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
                          child: Image(image: NetworkImage(c.image)),
                        ),
                        title: Text(c.name, style: const TextStyle(color: Colors.grey),),
                      ));
                      columnWidgets.add(const Divider());
                    }
                    columnWidgets.add(ListTile(
                      title: Container(
                          padding: EdgeInsets.only(left: MediaQuery.of(context).textScaleFactor * 24),
                          child: Text(getDeviceTitle(i))),
                    ));
                    return Column(
                      children: columnWidgets,
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
