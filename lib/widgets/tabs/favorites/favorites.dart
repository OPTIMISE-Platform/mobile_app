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
import 'package:mobile_app/models/device_group.dart';
import 'package:mobile_app/services/haptic_feedback_proxy.dart';
import 'package:provider/provider.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../../../app_state.dart';
import '../../../services/settings.dart';
import '../../../theme.dart';
import '../../shared/delay_circular_progress_indicator.dart';
import '../device_tabs.dart';
import '../shared/device_list_item.dart';
import '../shared/group_list_item.dart';

class DeviceListFavorites extends StatefulWidget {
  const DeviceListFavorites({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _DeviceListFavoritesState();
}

class _DeviceListFavoritesState extends State<DeviceListFavorites> with WidgetsBindingObserver {
  final GlobalKey _keyFavButton = GlobalKey();
  StreamSubscription? _refreshSubscription;
  bool _init = false;

  _openFavorites(BuildContext context) {
    final parentState = context.findAncestorStateOfType<State<DeviceTabs>>() as DeviceTabsState?;
    parentState?.switchBottomBar(5, true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshSubscription?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshSubscription = AppState().refreshPressed.listen((_) {
      AppState().refreshDevices(context);
    });
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
    return Consumer<AppState>(builder: (context, state, child) {
      if (state.initialized && state.devices.isEmpty && !_init) {
        state.loadDevices(context);
        _init = true;
      }
      final List<DeviceGroup> matchingGroups = [];
      for (var i = 0; i < state.deviceGroups.length; i++) {
        if (state.deviceGroups[i].favorite) {
          matchingGroups.add(state.deviceGroups[i]);
        }
      }
      final devices = state.devices.where((element) => element.favorite).toList();
      if (devices.isEmpty && matchingGroups.isEmpty && !state.loadingDevices) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _showTutorial(context));
      }
      Widget? child;
      if (devices.isEmpty) {
        if (state.loadingDevices) {
          child = const Center(child: DelayedCircularProgressIndicator());
        } else if (matchingGroups.isEmpty) {
          Center(child: LayoutBuilder(
            builder: (context, constraint) {
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraint.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      children: [
                        Expanded(
                            child: Center(
                                child: PlatformElevatedButton(
                          widgetKey: _keyFavButton,
                          child: const Text("Add Favorites"),
                          onPressed: () => _openFavorites(context),
                        ))),
                      ],
                    ),
                  ),
                ),
              );
            },
          ));
        }
      }
      child ??= ListView.builder(
          padding: MyTheme.inset,
          itemCount: state.totalDevices + matchingGroups.length,
          itemBuilder: (_, i) {
            if (i > devices.length + matchingGroups.length - 1) {
              return const SizedBox.shrink();
            }
            if (i < devices.length) {
              return Column(
                children: [const Divider(), DeviceListItem(devices[i], null)],
              );
            }
            return Column(
              children: [
                const Divider(),
                GroupListItem(matchingGroups.elementAt(i - devices.length), (_) {
                  final parentState = context.findAncestorStateOfType<State<DeviceTabs>>() as DeviceTabsState?;
                  if (parentState == null) return;
                  parentState.filter.deviceGroupIds = null;
                  state.searchDevices(parentState.filter, context);
                })
              ],
            );
          },
        );
      return RefreshIndicator(
          onRefresh: () async {
            HapticFeedbackProxy.lightImpact();
            state.refreshDevices(context);
          },
          child: Scrollbar(child: child));
    });
  }

  void _showTutorial(BuildContext context) {
    if (!Settings.tutorialSeen(Tutorial.addFavoriteButton)) {
      TutorialCoachMark(
        targets: [
          TargetFocus(keyTarget: _keyFavButton, contents: [
            TargetContent(
              align: ContentAlign.top,
              child: const Text(
                "Add some devices to your favorites for quick access",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24),
              ),
              padding: const EdgeInsets.only(bottom: 75, left: 20, right: 20),
            )
          ])
        ],
        colorShadow: MyTheme.appColor,
        onClickTarget: (_) {
          _openFavorites(context);
        },
        alignSkip: Alignment.topRight,
      ).show(context: context);
      Settings.markTutorialSeen(Tutorial.addFavoriteButton);
    }
  }
}
