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
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:mobile_app/models/smart_service.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/services/smart_service.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/base.dart';
import 'package:uuid/uuid.dart';

import '../../../app_state.dart';
import '../../../theme.dart';
import '../../shared/expandable_fab.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => DashboardState();
}

class DashboardState extends State<Dashboard> with WidgetsBindingObserver, TickerProviderStateMixin {
  static const double heightUnit = 64;
  static const Duration animationDuration = Duration(milliseconds: 100);

  Map<String, SmartServiceModuleWidget>? _smartServiceWidgets;
  final List<SmartServiceDashboard> _dashboards = Settings.getSmartServiceDashboards();

  TabController? _tabController;
  bool _showFab = false;
  final StreamController _toggleStreamController = StreamController();
  late final Stream _toggleStream;
  bool _newDashboardDialogOpen = false;

  DashboardState() {
    _toggleStream = _toggleStreamController.stream.asBroadcastStream();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final modules = await SmartServiceService.getModules(type: smartServiceModuleTypeWidget);
      final items = modules.map((e) => SmartServiceModuleWidget.fromModule(e)).where((element) => element != null);
      _smartServiceWidgets = {};
      items.forEach((element) => _smartServiceWidgets![element!.id] = element);
      setState(() {});
      _refresh();
    });
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(
      initialIndex: 0,
      length: 0,
      vsync: this,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && ModalRoute.of(context)?.isCurrent == true) {
      AppState().refreshDevices(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalBuildWith = MediaQuery.of(context).size.width;

    // Add all configured dashboards
    final tabHeaders = _dashboards
        .map((e) => Tab(
              icon: Text(e.name),
            ))
        .toList();

    final tabs = List<Widget>.generate(
        _dashboards.length,
        (index) => SingleChildScrollView(
            scrollDirection: Axis.vertical, child: Container(width: MediaQuery.of(context).size.width, child: _tabBody(index))));

    // Add dashboard with all widgets
    tabHeaders.add(const Tab(
      icon: Text("All"),
    ));
    final items = _smartServiceWidgets?.values.toList() ?? [];
    tabs.add(SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: SizedBox(
                height: MediaQuery.of(context).size.height - 192,
                width: MediaQuery.of(context).size.width,
                child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, idx) {
                      final item = items[idx];
                      return AnimatedContainer(
                        duration: animationDuration,
                        height: item.height * heightUnit,
                        width: MediaQuery.of(context).size.width,
                        child: Card(
                            child: SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: item.build(context, false),
                        )),
                      );
                    })))));

    // Add button for new dashboard
    tabHeaders.add(Tab(
      icon: Icon(PlatformIcons(context).add),
    ));
    tabs.add(const Tab(
      child: SizedBox.shrink(),
    ));

    if (_tabController?.length != _dashboards.length + 2) {
      _tabController?.dispose();
      _tabController = TabController(
        initialIndex: 0,
        length: _dashboards.length + 2,
        vsync: this,
      );
      _tabController!.addListener(() async {
        if (_tabController!.index >= _dashboards.length && _showFab) {
          setState(() => _showFab = false);
        } else if (_tabController!.index < _dashboards.length && !_showFab) {
          setState(() => _showFab = true);
        }
        if (_tabController!.index == _dashboards.length + 1 && !_newDashboardDialogOpen) {
          final titleController = TextEditingController(text: "");
          String? newName;
          _newDashboardDialogOpen = true;
          await showPlatformDialog(
              context: context,
              builder: (_) => PlatformAlertDialog(
                    title: const Text("New Dashboard"),
                    content: PlatformTextFormField(controller: titleController, hintText: "Name"),
                    actions: [
                      PlatformDialogAction(
                        child: PlatformText('Cancel'),
                        onPressed: () => Navigator.pop(context),
                      ),
                      PlatformDialogAction(
                          child: PlatformText('Create'),
                          onPressed: () {
                            newName = titleController.value.text;
                            Navigator.pop(context, titleController.value.text);
                          })
                    ],
                  ));
          _newDashboardDialogOpen = false;
          if (newName != null) {
            _dashboards.add(SmartServiceDashboard(const Uuid().v4(), titleController.text, []));
            Settings.setSmartServiceDashboards(_dashboards);
            setState(() {}); // Refresh _tabController
            WidgetsBinding.instance.addPostFrameCallback((_) {
              setState(() {
                _tabController?.index = _dashboards.length - 1; // switch to new tab
              });
              _addWidget(totalBuildWith);
            });
          } else {
            WidgetsBinding.instance.addPostFrameCallback((_) => setState(() {
                  _tabController?.index = _tabController!.previousIndex;
                }));
          }
        }
      });
    }

    _showFab = _tabController!.index < _dashboards.length;
    final fab = ExpandableFab(
      icon: Icon(Icons.edit, color: MyTheme.textColor),
      distance: 90.0,
      toggleStream: _toggleStream,
      children: [
        ActionButton(
          onPressed: () async {
            await _addWidget(totalBuildWith);
            _toggleStreamController.add(null);
          },
          icon: Icon(Icons.add, color: MyTheme.textColor),
        ),
        ActionButton(
          onPressed: () async {
            final titleController = TextEditingController(text: _dashboards[_tabController!.index].name);
            String? newName;
            _newDashboardDialogOpen = true;
            newName = await showPlatformDialog(
                context: context,
                builder: (_) => PlatformAlertDialog(
                      title: const Text("Rename Dashboard"),
                      content: PlatformTextFormField(controller: titleController, hintText: "Name"),
                      actions: [
                        PlatformDialogAction(
                          child: PlatformText('Cancel'),
                          onPressed: () => Navigator.pop(context),
                        ),
                        PlatformDialogAction(
                            child: PlatformText('Save'),
                            onPressed: () {
                              newName = titleController.value.text;
                              Navigator.pop(context, titleController.value.text);
                            })
                      ],
                    ));
            _toggleStreamController.add(null);
            if (newName == null) {
              return;
            }
            _dashboards[_tabController!.index].name = newName!;
            Settings.setSmartServiceDashboards(_dashboards);
            setState(() {});
          },
          icon: Icon(Icons.drive_file_rename_outline, color: MyTheme.textColor),
        ),
        ActionButton(
          onPressed: () async {
            final delete = await showPlatformDialog(
                context: context,
                builder: (context) => PlatformAlertDialog(
                      title: Text("Do you want to permanently delete dashboard '" + _dashboards[_tabController!.index].name + "'?"),
                      actions: [
                        PlatformDialogAction(
                          child: PlatformText('Cancel'),
                          onPressed: () => Navigator.pop(context),
                        ),
                        PlatformDialogAction(
                            child: PlatformText('Delete'),
                            cupertino: (_, __) => CupertinoDialogActionData(isDestructiveAction: true),
                            onPressed: () async {
                              Navigator.pop(context, true);
                            })
                      ],
                    ));
            if (delete != true) return;
            _dashboards.removeAt(_tabController!.index);
            Settings.setSmartServiceDashboards(_dashboards);
            _toggleStreamController.add(null);
            setState(() {});
          },
          color: MyTheme.warnColor,
          icon: Icon(Icons.delete, color: MyTheme.textColor),
        )
      ],
    );
    return Scaffold(
      floatingActionButton: !_showFab
          ? null
          : PlatformWidget(material: (_, __) => fab, cupertino: (_, __) => Container(margin: const EdgeInsets.only(bottom: 55), child: fab)),
      appBar: TabBar(
        isScrollable: true,
        tabs: tabHeaders,
        controller: _tabController,
      ),
      body: TabBarView(
        controller: _tabController,
        children: tabs,
      ),
    );
  }

  Widget _tabBody(int tabIdx) {
    final List<String> missingIds = [];
    final items = _smartServiceWidgets == null
        ? <SmartServiceModuleWidget>[]
        : _dashboards[tabIdx]
            .widgetIds
            .map((e) {
              if (_smartServiceWidgets!.containsKey(e)) {
                return _smartServiceWidgets![e];
              } else {
                missingIds.add(e);
                return null;
              }
            })
            .where((element) => element != null)
            .toList();
    if (missingIds.isNotEmpty) {
      _dashboards[tabIdx].widgetIds.removeWhere((e) => missingIds.contains(e));
      Settings.setSmartServiceDashboards(_dashboards);
    }

    return RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: Container(
            //SizedBox does not work here
            height: MediaQuery.of(context).size.height - 192,
            child: ReorderableListView.builder(
              itemCount: items.length,
              itemBuilder: (context, idx) {
                final item = items[idx]!;
                return Dismissible(
                    key: ValueKey(_dashboards[tabIdx].widgetIds.toString() + "_" + idx.toString()),
                    // key needs to stay the same while dragging but change when deleting
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: MyTheme.inset,
                      color: MyTheme.warnColor,
                      child: Icon(
                        PlatformIcons(context).delete,
                        color: Colors.white,
                      ),
                    ),
                    direction: DismissDirection.endToStart,
                    onDismissed: (_) {
                      items.removeAt(idx);
                      _dashboards[tabIdx].widgetIds = items.map((e) => e!.id).toList();
                      Settings.setSmartServiceDashboards(_dashboards);
                      setState(() {});
                    },
                    child: AnimatedContainer(
                        duration: animationDuration,
                        height: item.height * heightUnit,
                        width: MediaQuery.of(context).size.width,
                        child: Card(
                            child: SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: item.build(context, false),
                        ))));
              },
              onReorder: (int oldIndex, int newIndex) async {
                final tmp = items[oldIndex];
                items.removeAt(oldIndex);
                items.insert(newIndex - (oldIndex < newIndex ? 1 : 0), tmp);
                _dashboards[tabIdx].widgetIds = items.map((e) => e!.id).toList();
                await Settings.setSmartServiceDashboards(_dashboards);
              },
            )));
  }

  Future<void> _addWidget(double totalBuildWith) async {
    final items = _smartServiceWidgets?.values.toList() ?? [];
    final newId = await showPlatformDialog(
        context: context,
        builder: (context) {
          return PlatformAlertDialog(
              title: const Text("Add Widget"),
              content: SizedBox(
                  width: MediaQuery.of(context).size.width,
                  child: ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, idx) {
                        final item = items[idx];
                        return AnimatedContainer(
                            duration: animationDuration,
                            key: ValueKey(item.id),
                            height: item.height * heightUnit * (MediaQuery.of(context).size.width / totalBuildWith),
                            width: MediaQuery.of(context).size.width,
                            child: GestureDetector(
                              child: Card(
                                elevation: 2,
                                child: item.build(context, true),
                              ),
                              onTap: () => Navigator.pop(context, item.id),
                            ));
                      })));
        });
    if (newId == null) return;
    _dashboards[_tabController!.index].widgetIds.add(newId);
    Settings.setSmartServiceDashboards(_dashboards);
    setState(() {});
  }

  _refresh() async {
    List<SmartServiceModuleWidget?> items = _smartServiceWidgets?.values.toList() ?? [];
    if ((_tabController?.index ?? 0) < _dashboards.length) {
      items = _getTabWidgets(_tabController?.index ?? 0);
    }
    final List<Future> futures = [];
    items.forEach((e) => futures.add(__refreshWidget(e)));
    setState(() {});
    await Future.wait(futures);
  }

  Future<void> __refreshWidget(SmartServiceModuleWidget? w) async {
    if (w == null) {
      return;
    }
    await w.refresh();
    setState(() {});
  }

  List<SmartServiceModuleWidget?> _getTabWidgets(int idx) {
    final List<String> missingIds = [];
    final items = _smartServiceWidgets == null
        ? <SmartServiceModuleWidget>[]
        : _dashboards[idx]
            .widgetIds
            .map((e) {
              if (_smartServiceWidgets!.containsKey(e)) {
                return _smartServiceWidgets![e];
              } else {
                missingIds.add(e);
                return null;
              }
            })
            .where((element) => element != null)
            .toList();
    if (missingIds.isNotEmpty) {
      _dashboards[idx].widgetIds.removeWhere((e) => missingIds.contains(e));
      Settings.setSmartServiceDashboards(_dashboards);
    }
    return items;
  }
}
