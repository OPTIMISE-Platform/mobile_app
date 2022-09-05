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
import 'package:mobile_app/services/locations.dart';
import 'package:mobile_app/widgets/tabs/locations/location_page.dart';
import 'package:provider/provider.dart';

import '../../../app_state.dart';
import '../../../models/device_search_filter.dart';
import '../../../services/haptic_feedback_proxy.dart';
import '../../../theme.dart';
import '../device_tabs.dart';

class DeviceListByLocation extends StatefulWidget {
  const DeviceListByLocation({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _DeviceListByLocationState();
}

class _DeviceListByLocationState extends State<DeviceListByLocation> with WidgetsBindingObserver {
  static StreamSubscription? _fabSubscription;

  @override
  void dispose() {
    _fabSubscription?.cancel().then((_) => _fabSubscription = null);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && ModalRoute.of(context)?.isCurrent == true) {
      AppState().loadLocations(context);
      setState(() {});
    }
  }

  void _openLocationPage(int i, DeviceTabsState? parentState) async {
    parentState?.filter.locationIds = [AppState().locations[i].id];
    AppState().searchDevices(parentState?.filter ?? DeviceSearchFilter("", null, null, null, [AppState().locations[i].id]), context);
    await Navigator.push(context, platformPageRoute(context: context, builder: (context) => LocationPage(i, parentState!)));
    parentState?.filter.locationIds = null;
  }

  @override
  Widget build(BuildContext _) {
    return Consumer<AppState>(builder: (_, state, child) {
      final parentState = context.findAncestorStateOfType<State<DeviceTabs>>() as DeviceTabsState?;
      _fabSubscription ??= parentState?.fabPressed.listen((_) async {
        final titleController = TextEditingController(text: "");
        String? newName;
        await showPlatformDialog(
            context: context,
            builder: (_) => PlatformAlertDialog(
                  title: const Text("New Location"),
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
                          Navigator.popUntil(context, (route) => route.isFirst);
                        })
                  ],
                ));
        if (newName == null) {
          return;
        }

        state.locations.add(await LocationService.createLocation(newName!));
        _openLocationPage(state.locations.length - 1, parentState);
        state.notifyListeners();
      });
      return Scrollbar(
          child: state.loadingLocations()
              ? Center(child: PlatformCircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: () async {
                    HapticFeedbackProxy.lightImpact();
                    state.loadLocations(context);
                  },
                  child: state.locations.isEmpty
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
                                        child: Center(child: Text("No Locations")),
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
                          itemCount: state.locations.length + 1,
                          itemBuilder: (context, i) {
                            return i < state.locations.length
                                ? Column(children: [
                                    const Divider(),
                                    ListTile(
                                        title: Text(state.locations[i].name),
                                        leading: Container(
                                          height: MediaQuery.of(context).textScaleFactor * 48,
                                          width: MediaQuery.of(context).textScaleFactor * 48,
                                          decoration: BoxDecoration(color: const Color(0xFF6c6c6c), borderRadius: BorderRadius.circular(50)),
                                          child: Padding(
                                            padding: EdgeInsets.all(MediaQuery.of(context).textScaleFactor * 8),
                                            child: state.locations[i].imageWidget ?? Icon(PlatformIcons(context).location, color: Colors.white),
                                          ),
                                        ),
                                        subtitle: Text(
                                            "${state.locations[i].device_ids.length} Device${state.locations[i].device_ids.length > 1 || state.locations[i].device_ids.isEmpty ? "s" : ""}, ${state.locations[i].device_group_ids.length} Group${state.locations[i].device_group_ids.length > 1 || state.locations[i].device_group_ids.isEmpty ? "s" : ""}"),
                                        onTap: () => _openLocationPage(i, parentState))
                                  ])
                                : Column(
                                    children: const [Divider(), ListTile()],
                                  );
                          },
                        )));
    });
  }
}
