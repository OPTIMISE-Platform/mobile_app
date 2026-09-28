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
import 'package:mobile_app/mixins/resume_refresh_mixin.dart';

import 'package:flutter/material.dart';
import 'package:mobile_app/services/haptic_feedback_proxy.dart';
import 'package:mobile_app/services/smart_service.dart';
import 'package:mobile_app/widgets/tabs/smart-services/releases.dart';
import 'package:mutex/mutex.dart';

import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/smart_service.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/shared/grouped_list_tile.dart';
import 'package:mobile_app/widgets/shared/sectioned_list_view.dart';
import 'package:mobile_app/widgets/tabs/device_tabs.dart';
import 'package:mobile_app/widgets/tabs/smart-services/instance_details.dart';
import 'package:mobile_app/widgets/tabs/smart-services/instance_edit_launch.dart';

import '../../shared/toast.dart';

class SmartServicesInstances extends StatefulWidget {
  const SmartServicesInstances({super.key});

  @override
  State<StatefulWidget> createState() => _SmartServicesInstancesState();
}

class _SmartServicesInstancesState extends State<SmartServicesInstances>
    with ResumeRefreshMixin {
  bool allInstancesLoaded = false;
  final List<SmartServiceInstance> instances = [];
  // Keyed by instance id, not position: a refresh while an upgrade runs
  // reorders or drops rows, and the spinner must stay with its instance.
  final Set<String> _upgradingIds = {};
  Mutex instancesMutex = Mutex();
  StreamSubscription? _fabSubscription;
  StreamSubscription? _refreshSubscription;
  late final DeviceTabsState? parentState;

  @override
  void dispose() {
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
      if (!mounted) return;
      await Navigator.push(
          context,
          MaterialPageRoute(
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
  }

  @override
  void onResumed() => _refresh();

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
      final newInstances =
          await SmartServiceService.getInstances(limit, instances.length);
      instances.addAll(newInstances);
      allInstancesLoaded = newInstances.length < limit;
    });
    setState(() {});
  }

  /// Upgrades [instance], the object of the tapped row: an index taken at tap
  /// time names another instance once a refresh has reordered the list.
  Future<void> _upgrade(BuildContext context, SmartServiceInstance instance) async {
    final id = instance.id;
    setState(() => _upgradingIds.add(id));
    try {
      final p = await SmartServiceService.prepareUpgrade(instance);
      if (!p.t) {
        await SmartServiceService.updateInstanceParameters(
            id, p.k.map((e) => e.toSmartServiceParameter()).toList(),
            releaseId: instance.new_release_id);
      } else {
        final release =
            await SmartServiceService.getRelease(instance.new_release_id!);
        if (context.mounted) {
          await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => SmartServicesReleaseLaunch(
                        release,
                        instance: instance,
                        parameters: p.k,
                      )));
        }
      }
    } catch (e) {
      Toast.showToastNoContext("Upgrade was not possible: $e");
    }
    if (!mounted) return;
    setState(() => _upgradingIds.remove(id));
    if (_upgradingIds.isEmpty) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
        child: instancesMutex.isLocked
            ? const Center(child: DelayedCircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: () async {
                  if (_upgradingIds.isNotEmpty) return;
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
                    : SectionedListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        sections: [
                          ListSection<SmartServiceInstance>(
                            id: "instances",
                            items: instances,
                            keyOf: (instance) => instance.id,
                            itemBuilder: (context, instance, position) {
                              if (position.roundsBottom && !allInstancesLoaded) {
                                _loadInstances();
                              }
                              return GroupedListTile(
                                position: position,
                                hairlineInset:
                                    GroupedListTile.insetNoLeading,
                                child: ListTile(
                                  title: Row(children: [
                                    Text(instance.name),
                                    Badge(
                                      // backgroundColor below is
                                      // transparent, so this icon sits
                                      // directly on the page surface.
                                      label: instance.error != null
                                          ? Icon(Icons.error,
                                              size: 16,
                                              color: context.appColors.warnInk)
                                          : const Icon(Icons.pending,
                                              size: 16,
                                              color: Colors.lightBlue),
                                      isLabelVisible:
                                          instance.error != null ||
                                              !instance.ready ||
                                              instance.deleting == true,
                                      alignment:
                                          AlignmentDirectional.topCenter,
                                      largeSize: 16,
                                      backgroundColor: Colors.transparent,
                                      child: instance.error != null ||
                                              !instance.ready ||
                                              instance.deleting == true
                                          ? const Text("")
                                          : null,
                                    )
                                  ]),
                                  onTap: () async {
                                    await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              SmartServicesInstanceDetails(
                                                  instance,
                                                  parentState?.context),
                                        ));
                                          _refresh();
                                        },
                                        trailing: instance.new_release_id ==
                                                null
                                            ? null
                                            : _upgradingIds.contains(instance.id)
                                                ? const DelayedCircularProgressIndicator()
                                                : IconButton(
                                                    icon: const Icon(Icons.upgrade),
                                                    onPressed: () => _upgrade(context, instance),
                                                  ),
                                      ));
                            },
                          ),
                        ],
                        // Sized like the row+divider it replaces, so the last
                        // instance isn't hidden behind the FAB.
                        trailing: const [SizedBox(height: 72)],
                      )));
  }
}
