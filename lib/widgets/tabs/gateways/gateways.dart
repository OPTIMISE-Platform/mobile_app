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
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/services/haptic_feedback_proxy.dart';
import 'package:mobile_app/services/mgw/storage.dart';
import 'package:mobile_app/widgets/tabs/gateways/mgw_page.dart';
import 'package:mobile_app/widgets/tabs/gateways/details.dart';

import 'package:provider/provider.dart';

import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/device_instance.dart';
import 'package:mobile_app/models/device_search_filter.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/tabs/device_tabs.dart';
import 'package:mobile_app/widgets/tabs/shared/device_list_item.dart';

class Gateways extends StatefulWidget {
  const Gateways({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _GatewaysState();
}

class _GatewaysState extends State<Gateways> with WidgetsBindingObserver {
  int? _selected;
  bool _loading = false;
  StreamSubscription? _refreshSubscription;
  StreamSubscription? _fabSubscription;
  late final DeviceTabsState? parentState;

  _refresh() async {
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshSubscription = AppState().refreshPressed.listen((_) {
      _refresh();
    });
    parentState = context.findAncestorStateOfType<State<DeviceTabs>>()
    as DeviceTabsState?;
    _fabSubscription = parentState?.fabPressed.listen((_) async {
      await Navigator.push(
          context,
          platformPageRoute(
            context: context,
            builder: (context) {
              final target = const AddLocalNetwork();
              return target;
            },
          ));
      _refresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshSubscription?.cancel();
    _fabSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && ModalRoute.of(context)?.isCurrent == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(builder: (context, state, child) {
      return Scrollbar(
              child: state.gateways.isEmpty
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
                                  child: Center(child: Text("No Gateways")),
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
                    itemCount: state.gateways.length,
                    itemBuilder: (context, i) {
                      var mgw = state.gateways[i];

                      return Column(children: [
                        i > 0 ? const Divider() : const SizedBox.shrink(),
                        ListTile(
                            title: Row(children: [
                              Text(state.gateways[i].mDNSServiceName),
                            ]),
                          onTap: () {
                              Navigator.push(context, MaterialPageRoute(builder: (context) => MGWDetail(mgw: mgw)));
                          },
                          trailing: MaterialButton(
                              child: Icon(
                                  Icons.delete
                              ),
                              onPressed: () async {
                                await MgwStorage.RemovePairedMGW(mgw);
                                await state.loadStoredMGWs();
                              }
                          ),
                        )]);
                    },
              )
      );
    });
  }
}
