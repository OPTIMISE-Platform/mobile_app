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
import 'package:mobile_app/services/mgw/storage.dart';
import 'package:mobile_app/widgets/tabs/gateways/mgw_page.dart';
import 'package:mobile_app/widgets/tabs/gateways/details.dart';

import 'package:provider/provider.dart';

import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/tabs/device_tabs.dart';

class Gateways extends StatefulWidget {
  const Gateways({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _GatewaysState();
}

class _GatewaysState extends State<Gateways> with ResumeRefreshMixin {
  StreamSubscription? _refreshSubscription;
  StreamSubscription? _fabSubscription;
  late final DeviceTabsState? parentState;

  _refresh() async {
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _refreshSubscription = AppState().refreshPressed.listen((_) {
      _refresh();
    });
    parentState = context.findAncestorStateOfType<State<DeviceTabs>>()
        as DeviceTabsState?;
    _fabSubscription = parentState?.fabPressed.listen((_) async {
      if (!mounted) return;
      await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) {
              const target = AddLocalNetwork();
              return target;
            },
          ));
      _refresh();
    });
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
                        constraints:
                            BoxConstraints(minHeight: constraint.maxHeight),
                        child: const IntrinsicHeight(
                          child: Column(
                            children: [
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
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => MGWDetail(mgw: mgw)));
                        },
                        trailing: MaterialButton(
                            child: const Icon(Icons.delete),
                            onPressed: () async {
                              await MgwStorage.RemovePairedMGW(mgw);
                              await state.loadStoredMGWs();
                            }),
                      )
                    ]);
                  },
                ));
    });
  }

  @override
  void onResumed() => _refresh();

  @override
  void dispose() {
    _refreshSubscription?.cancel();
    _fabSubscription?.cancel();
    super.dispose();
  }
}
