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

import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:provider/provider.dart';

import '../../../app_state.dart';
import '../../../theme.dart';
import '../shared/device_list_item.dart';

class DeviceList extends StatefulWidget {
  const DeviceList({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _DeviceListState();
}

class _DeviceListState extends State<DeviceList> with WidgetsBindingObserver {
  @override
  void dispose() {
    WidgetsBinding.instance!.removeObserver(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance!.addObserver(this);
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
    return Consumer<AppState>(
        builder: (_, __, ___) => RefreshIndicator(
              onRefresh: () => AppState().refreshDevices(context),
              child: Scrollbar(
                child: AppState().loadingDevices
                    ? Center(child: PlatformCircularProgressIndicator())
                    : AppState().devices.isEmpty
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
                                          child: Center(child: Text("No Devices")),
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
                            itemCount: AppState().totalDevices,
                            itemBuilder: (context, i) {
                              if (i >= AppState().devices.length) {
                                AppState().loadDevices(context);
                              }
                              if (i > AppState().devices.length - 1) {
                                return const SizedBox.shrink();
                              }
                              return Column(children: [
                                const Divider(),
                                DeviceListItem(i, null),
                              ]);
                            }),
              ),
            ));
  }
}
