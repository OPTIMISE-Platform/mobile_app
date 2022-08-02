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
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:mobile_app/services/smart_service.dart';
import 'package:mobile_app/widgets/tabs/smart-services/releases.dart';
import 'package:mutex/mutex.dart';

import '../../../models/smart_service.dart';
import '../../../theme.dart';
import '../device_tabs.dart';
import 'instance_details.dart';

class SmartServicesInstances extends StatefulWidget {
  const SmartServicesInstances({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _SmartServicesInstancesState();
}

class _SmartServicesInstancesState extends State<SmartServicesInstances> with WidgetsBindingObserver {
  bool allInstancesLoaded = false;
  final List<SmartServiceInstance> instances = [];
  Mutex instancesMutex = Mutex();
  static StreamSubscription? _fabSubscription;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fabSubscription?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final parentState = context.findAncestorStateOfType<State<DeviceTabs>>() as DeviceTabsState?;
    _fabSubscription = parentState?.fabPressed.listen((_) async {
      await Navigator.push(
          context,
          platformPageRoute(
            context: context,
            builder: (context) {
              final target = const SmartServicesReleases();
              return target;
            },
          ));
      _refresh();
    });
    _refresh();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && ModalRoute.of(context)?.isCurrent == true) {
      _refresh();
    }
  }

  _refresh() async {
    instances.clear();
    allInstancesLoaded = false;
    final f = _loadInstances();
    setState(() {});
    await f;
  }

  _loadInstances() async {
    if (allInstancesLoaded || instancesMutex.isLocked) {
      return;
    }
    await instancesMutex.protect(() async {
      const limit = 50;
      final newInstances = await SmartServiceService.getInstances(limit, instances.length);
      instances.addAll(newInstances);
      allInstancesLoaded = newInstances.length < limit;
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
        child: instancesMutex.isLocked
            ? Center(child: PlatformCircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: () async => await _refresh(),
                child: instances.isEmpty
                    ? LayoutBuilder(
                        builder: (context, constraint) {
                          return SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minHeight: constraint.maxHeight),
                              child: IntrinsicHeight(
                                child: Column(
                                  children: const [
                                    Expanded(
                                      child: Center(child: Text("No Instances")),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: MyTheme.inset,
                        itemCount: instances.length,
                        itemBuilder: (context, i) {
                          if (i == instances.length - 1 && !allInstancesLoaded) {
                            _loadInstances();
                          }
                          return Column(children: [
                            const Divider(),
                            ListTile(
                                title: Container(
                                    alignment: Alignment.centerLeft,
                                    child: Badge(
                                      alignment: Alignment.centerLeft,
                                      padding: const EdgeInsets.only(left: MyTheme.insetSize),
                                      position: BadgePosition.topEnd(),
                                      badgeContent: instances[i].error != null
                                          ? Icon(PlatformIcons(context).error, size: 16, color: MyTheme.warnColor)
                                          : const Icon(Icons.pending, size: 16, color: Colors.lightBlue),
                                      showBadge: instances[i].error != null || !instances[i].ready,
                                      badgeColor: Colors.transparent,
                                      elevation: 0,
                                      child: Text(instances[i].name),
                                    )),
                                onTap: () async {
                                  await Navigator.push(
                                      context,
                                      platformPageRoute(
                                        context: context,
                                        builder: (context) => SmartServicesInstanceDetails(instances[i]),
                                      ));
                                  _refresh();
                                })
                          ]);
                        },
                      )));
  }
}
