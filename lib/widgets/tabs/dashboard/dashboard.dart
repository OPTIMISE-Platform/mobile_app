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
import 'package:mobile_app/services/haptic_feedback_proxy.dart';
import 'package:mobile_app/services/settings.dart';
import 'package:mobile_app/services/smart_service.dart';
import 'package:mobile_app/widgets/tabs/dashboard/smart_service_widgets/base.dart';
import 'package:uuid/uuid.dart';

import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/exceptions/unexpected_status_code_exception.dart';
import 'package:mobile_app/shared/keyed_list.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/expandable_fab.dart';

const double heightUnit = 32;

class Dashboard extends StatefulWidget {
  const Dashboard({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => DashboardState();
}

class DashboardState extends State<Dashboard> with WidgetsBindingObserver, TickerProviderStateMixin {
  Map<String, SmartServiceModuleWidget>? _smartServiceWidgets;
  final List<SmartServiceDashboard> _dashboards = Settings.getSmartServiceDashboards();

  TabController? _tabController;
  bool _showFab = false;
  final StreamController _toggleStreamController = StreamController();
  late final Stream _toggleStream;
  bool _newDashboardDialogOpen = false;

  StreamSubscription? _refreshSubscription;

  DashboardState() {
    _toggleStream = _toggleStreamController.stream.asBroadcastStream();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshSubscription?.cancel();
    _toggleStreamController.close();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final modules = await SmartServiceService.getModules(type: smartServiceModuleTypeWidget);
      final items = await Future.wait(modules.map((e) async => await SmartServiceModuleWidget.fromModule(e)).where((element) => element != null));
      _smartServiceWidgets = {};
      items.forEach((element) {
        if (element == null) return;
        _smartServiceWidgets![element.id] = element;
      });
      if (mounted) setState(() {});
      _refresh();
    });
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(
      initialIndex: 0,
      length: 0,
      vsync: this,
    );
    _refreshSubscription = AppState().refreshPressed.listen((_) {
      _refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
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
            onRefresh: () async {
              HapticFeedbackProxy.lightImpact();
              _refresh();
            },
            child: SizedBox(
                height: MediaQuery.of(context).size.height - 192,
                width: MediaQuery.of(context).size.width,
                child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, idx) {
                      final item = items[idx];
                      return Stack(children: [Card(
                        child: item.build(context, false),
                      )]);
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
        if (_tabController!.index >= _dashboards.length && _showFab && mounted) {
          setState(() => _showFab = false);
        } else if (_tabController!.index < _dashboards.length && !_showFab && mounted) {
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
            if (mounted) setState(() {}); // Refresh _tabController
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _tabController?.index = _dashboards.length - 1; // switch to new tab
                });
              }
              _addWidget();
            });
          } else {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _tabController?.index = _tabController!.previousIndex;
                });
              }
            });
          }
        } else {
          _refresh();
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
            await _addWidget();
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
            if (mounted) setState(() {});
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
            if (mounted) setState(() {});
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
    final items = _smartServiceWidgets == null
        ? <SmartServiceModuleWidget>[]
        : _dashboards[tabIdx]
            .widgetAndInstanceIds
            .map((e) {
              if (_smartServiceWidgets!.containsKey(e.k)) {
                return _smartServiceWidgets![e.k];
              } else {
                return null;
              }
            })
            .where((element) => element != null)
            .toList();

    return RefreshIndicator(
        onRefresh: () async {
          HapticFeedbackProxy.lightImpact();
          _refresh();
        },
        child: Container(
            //SizedBox does not work here
            height: MediaQuery.of(context).size.height - 192,
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: items.length,
              itemBuilder: (context, idx) {
                final item = items[idx]!;
                return Dismissible(
                    key: ValueKey("${_dashboards[tabIdx].widgetAndInstanceIds}_$idx"),
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
                      _dashboards[tabIdx].widgetAndInstanceIds = items.map((e) => Pair(e!.id, e.instance_id)).toList();
                      Settings.setSmartServiceDashboards(_dashboards);
                      if (mounted) setState(() {});
                    },
                    child: Card(
                        child: Stack(children: [
                      item.build(context, false),
                      Positioned(
                          right: 8,
                          top: 4,
                          child: ReorderableDragStartListener(
                            index: idx,
                            child: _dashboards[tabIdx].widgetAndInstanceIds.length > 1
                                ? const Icon(Icons.reorder, color: Colors.grey)
                                : const SizedBox.shrink(),
                          ))
                    ])));
              },
              onReorder: (int oldIndex, int newIndex) async {
                final tmp = items[oldIndex];
                items.removeAt(oldIndex);
                items.insert(newIndex - (oldIndex < newIndex ? 1 : 0), tmp);
                _dashboards[tabIdx].widgetAndInstanceIds = items.map((e) => Pair(e!.id, e.instance_id)).toList();
                await Settings.setSmartServiceDashboards(_dashboards);
              },
            )));
  }

  Future<void> _addWidget() async {
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
                      itemBuilder: (context, idx) => GestureDetector(
                            child: Card(
                              elevation: 2,
                              child: items[idx].build(context, true),
                            ),
                            onTap: () => Navigator.pop(context, Pair(items[idx].id, items[idx].instance_id)),
                          ))));
        });
    if (newId == null) return;
    _dashboards[_tabController!.index].widgetAndInstanceIds.add(newId);
    Settings.setSmartServiceDashboards(_dashboards);
    if (mounted) setState(() {});
  }

  _refresh() async {
    List<SmartServiceModuleWidget?> items = _smartServiceWidgets?.values.toList() ?? [];
    if ((_tabController?.index ?? 0) < _dashboards.length) {
      items = _getTabWidgets(_tabController?.index ?? 0);
    }
    final List<Future> futures = [];
    items.forEach((e) => futures.add(__refreshWidget(e)));
    if (mounted) setState(() {});
    await Future.wait(futures);
  }

  Future<void> __refreshWidget(SmartServiceModuleWidget? w) async {
    if (w == null) {
      return;
    }
    await w.refresh();
    if (mounted) setState(() {});
  }

  List<SmartServiceModuleWidget?> _getTabWidgets(int idx) {
    final List<Pair<String, String>> missingIds = [];
    final items = _smartServiceWidgets == null
        ? <SmartServiceModuleWidget>[]
        : _dashboards[idx]
            .widgetAndInstanceIds
            .map((e) {
              if (_smartServiceWidgets!.containsKey(e.k)) {
                return _smartServiceWidgets![e.k];
              } else {
                missingIds.add(e);
                return null;
              }
            })
            .where((element) => element != null)
            .toList();
    if (missingIds.isNotEmpty) {
      // delay cleanup, not time critical
      Future.delayed(const Duration(seconds: 5)).then((_) => _cleanup(idx, missingIds));
    }
    return items;
  }

  _cleanup(int idx, List<Pair<String, String>> missingIds) async {
    final List<Future> futures = [];
    for (var p in missingIds) {
      futures.add(() async {
        try {
          final instance = await SmartServiceService.getInstance(p.t);
          // might still create widget if not ready
          if (instance.ready) {
            // widget might have been created in the meantime
            final modules = await Future.wait((await SmartServiceService.getModules(type: smartServiceModuleTypeWidget, instanceId: p.t))
                .map((e) => SmartServiceModuleWidget.fromModule(e))
                .toList(growable: false));
            final j = modules.indexWhere((e) => e?.id == p.k);
            if (j == -1) {
              _dashboards[idx].widgetAndInstanceIds.removeWhere((e) => e.k == p.k);
            } else if (mounted) {
              _smartServiceWidgets?[modules[j]!.id] = modules[j]!; // add widget to list
              __refreshWidget(modules[j]).then((_) {
                if (mounted) setState(() {}); //display widget
              });
            }
          }
        } on UnexpectedStatusCodeException catch (e) {
          if (e.code == 404) {
            // instance deleted
            _dashboards[idx].widgetAndInstanceIds.removeWhere((e) => e.k == p.k);
          } else {
            rethrow;
          }
        }
      }());
    }
    await Future.wait(futures);
    Settings.setSmartServiceDashboards(_dashboards);
  }
}
