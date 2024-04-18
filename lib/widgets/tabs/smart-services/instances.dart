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

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:mobile_app/services/haptic_feedback_proxy.dart';
import 'package:mobile_app/services/smart_service.dart';
import 'package:mobile_app/shared/keyed_list.dart';
import 'package:mobile_app/widgets/tabs/smart-services/releases.dart';
import 'package:mutex/mutex.dart';

import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/smart_service.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/tabs/device_tabs.dart';
import 'package:mobile_app/widgets/tabs/smart-services/instance_details.dart';
import 'package:mobile_app/widgets/tabs/smart-services/instance_edit_launch.dart';

import '../../shared/toast.dart';

class SmartServicesInstances extends StatefulWidget {
  const SmartServicesInstances({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _SmartServicesInstancesState();
}

class _SmartServicesInstancesState extends State<SmartServicesInstances>
    with WidgetsBindingObserver {
  bool allInstancesLoaded = false;
  final List<SmartServiceInstance> instances = [];
  List<bool> upgradingInstances = [];
  Mutex instancesMutex = Mutex();
  StreamSubscription? _fabSubscription;
  StreamSubscription? _refreshSubscription;
  late final DeviceTabsState? parentState;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fabSubscription?.cancel();
    _refreshSubscription?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    parentState = context.findAncestorStateOfType<State<DeviceTabs>>()
        as DeviceTabsState?;
    _fabSubscription = parentState?.fabPressed.listen((_) async {
      await Navigator.push(
          context,
          platformPageRoute(
            context: context,
            builder: (context) {
              const target = SmartServicesReleases();
              return target;
            },
          ));
      _refresh();
    });
    _refreshSubscription = AppState().refreshPressed.listen((_) {
      _refresh();
    });
    _refresh();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed &&
        ModalRoute.of(context)?.isCurrent == true) {
      _refresh();
    }
  }

  _refresh() async {
    instances.clear();
    upgradingInstances.clear();
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
      final newInstances =
          await SmartServiceService.getInstances(limit, instances.length);
      instances.addAll(newInstances);
      while (instances.length > upgradingInstances.length) {
        upgradingInstances.add(false);
      }
      allInstancesLoaded = newInstances.length < limit;
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
        child: instancesMutex.isLocked
            ? const Center(child: DelayedCircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: () async {
                  if (upgradingInstances.contains(true)) return;
                  HapticFeedbackProxy.lightImpact();
                  await _refresh();
                },
                child: instances.isEmpty
                    ? LayoutBuilder(
                        builder: (context, constraint) {
                          return SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                  minHeight: constraint.maxHeight),
                              child: const IntrinsicHeight(
                                child: Column(
                                  children: [
                                    Expanded(
                                      child:
                                          Center(child: Text("No Instances")),
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
                        itemCount: instances.length + 1,
                        itemBuilder: (context, i) {
                          if (i == instances.length - 1 &&
                              !allInstancesLoaded) {
                            _loadInstances();
                          }
                          return i < instances.length
                              ? Column(children: [
                                  i > 0
                                      ? const Divider()
                                      : const SizedBox.shrink(),
                                  ListTile(
                                    title: Row(children: [
                                      Text(instances[i].name),
                                      Badge(
                                        label: instances[i].error != null
                                            ? Icon(PlatformIcons(context).error,
                                                size: 16,
                                                color: MyTheme.warnColor)
                                            : const Icon(Icons.pending,
                                                size: 16,
                                                color: Colors.lightBlue),
                                        isLabelVisible:
                                            instances[i].error != null ||
                                                !instances[i].ready ||
                                                instances[i].deleting == true,
                                        alignment:
                                            AlignmentDirectional.topCenter,
                                        largeSize: 16,
                                        backgroundColor: Colors.transparent,
                                        child: instances[i].error != null ||
                                                !instances[i].ready ||
                                                instances[i].deleting == true
                                            ? const Text("")
                                            : null,
                                      )
                                    ]),
                                    onTap: () async {
                                      await Navigator.push(
                                          context,
                                          platformPageRoute(
                                            context: context,
                                            builder: (context) =>
                                                SmartServicesInstanceDetails(
                                                    instances[i],
                                                    parentState?.context),
                                          ));
                                      _refresh();
                                    },
                                    trailing: instances[i].new_release_id ==
                                            null
                                        ? null
                                        : upgradingInstances[i]
                                            ? const DelayedCircularProgressIndicator()
                                            : IconButton(
                                                icon: const Icon(Icons.upgrade),
                                                onPressed: () async {
                                                  setState(() {
                                                    upgradingInstances[i] =
                                                        true;
                                                  });
                                                  final Pair<List<SmartServiceExtendedParameter>, bool> p;
                                                  try {
                                                    p = await SmartServiceService
                                                        .prepareUpgrade(
                                                        instances[i]);
                                                    if (!p.t) {
                                                      await SmartServiceService
                                                          .updateInstanceParameters(
                                                          instances[i].id,
                                                          p.k
                                                              .map((e) => e
                                                              .toSmartServiceParameter())
                                                              .toList(),
                                                          releaseId: instances[
                                                          i]
                                                              .new_release_id);
                                                    } else {
                                                      final release =
                                                      await SmartServiceService
                                                          .getRelease(instances[
                                                      i]
                                                          .new_release_id!);
                                                      await Navigator.push(
                                                          context,
                                                          platformPageRoute(
                                                              context: context,
                                                              builder: (context) =>
                                                                  SmartServicesReleaseLaunch(
                                                                    release,
                                                                    instance:
                                                                    instances[
                                                                    i],
                                                                    parameters:
                                                                    p.k,
                                                                  )));
                                                    }
                                                  } catch (e) {
                                                    setState(() {
                                                      upgradingInstances[i] =
                                                          false;
                                                    });
                                                    Toast.showToastNoContext(
                                                        "Upgrade was not possible: ${e}");
                                                  }
                                                  upgradingInstances[i] = false;
                                                  if (!upgradingInstances
                                                      .contains(true))
                                                    _refresh();
                                                },
                                              ),
                                  )
                                ])
                              : const Column(children: [
                                  Divider(),
                                  ListTile(),
                                ]);
                        },
                      )));
  }
}
