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

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:intl/intl.dart';
import 'package:mobile_app/services/haptic_feedback_proxy.dart';
import 'package:mobile_app/services/smart_service.dart';
import 'package:mobile_app/widgets/shared/app_bar.dart';
import 'package:mobile_app/widgets/tabs/smart-services/instance_edit_launch.dart';
import 'package:mutex/mutex.dart';

import '../../../models/smart_service.dart';
import '../../../theme.dart';
import '../../shared/delay_circular_progress_indicator.dart';
import '../../shared/toast.dart';

class SmartServicesReleases extends StatefulWidget {
  const SmartServicesReleases({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _SmartServicesReleasesState();
}

class _SmartServicesReleasesState extends State<SmartServicesReleases>
    with WidgetsBindingObserver {
  bool allInstancesLoaded = false;
  final List<SmartServiceRelease> releases = [];
  Mutex releasesMutex = Mutex();

  final appBar = const MyAppBar("Releases");
  static final _format = DateFormat.yMd().add_jms();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
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
    releases.clear();
    allInstancesLoaded = false;
    await _loadInstances();
  }

  _loadInstances() async {
    if (allInstancesLoaded || releasesMutex.isLocked) {
      return;
    }
    await releasesMutex.protect(() async {
      const limit = 50;
      final newInstances =
          await SmartServiceService.getReleases(limit, releases.length);
      releases.addAll(newInstances);
      allInstancesLoaded = newInstances.length < limit;
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final actions = MyAppBar.getDefaultActions(context);
    if (kIsWeb) {
      actions.insert(
          0,
          PlatformIconButton(
            onPressed: () => _refresh(),
            icon: const Icon(Icons.refresh),
            cupertino: (_, __) =>
                CupertinoIconButtonData(padding: EdgeInsets.zero),
          ));
    }

    return PlatformScaffold(
        appBar: appBar.getAppBar(context, actions),
        body: Scrollbar(
            child: releasesMutex.isLocked
                ? const Center(child: DelayedCircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () async {
                      HapticFeedbackProxy.lightImpact();
                      await _refresh();
                    },
                    child: releases.isEmpty
                        ? LayoutBuilder(
                            builder: (context, constraint) {
                              return SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                      minHeight: constraint.maxHeight),
                                  child: IntrinsicHeight(
                                    child: Column(
                                      children: const [
                                        Expanded(
                                          child: Center(
                                              child: Text("No Releases")),
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
                            itemCount: releases.length,
                            itemBuilder: (context, i) {
                              if (i == releases.length - 1 &&
                                  !allInstancesLoaded) {
                                _loadInstances();
                              }
                              return Column(children: [
                                i > 0
                                    ? const Divider()
                                    : const SizedBox.shrink(),
                                ListTile(
                                    title: Row(children: [
                                      Text(
                                        releases[i].name,
                                        style: releases[i].usable == false
                                            ? const TextStyle(
                                                color: Colors.grey)
                                            : null,
                                      ),
                                      Badge(
                                        label: Icon(
                                            PlatformIcons(context).error,
                                            size: 16,
                                            color: MyTheme.warnColor),
                                        isLabelVisible:
                                            releases[i].error != null,
                                        alignment:
                                            AlignmentDirectional.topCenter,
                                        largeSize: 16,
                                        backgroundColor: Colors.transparent,
                                        child: releases[i].error != null
                                            ? const Text("")
                                            : null,
                                      )
                                    ]),
                                    subtitle: Text(_format
                                        .format(releases[i].createdAt())),
                                    onTap: releases[i].error != null ||
                                            releases[i].usable == false
                                        ? () => Toast.showWarningToast(context,
                                            "Missing devices for this service")
                                        : () => Navigator.push(
                                            context,
                                            platformPageRoute(
                                                context: context,
                                                builder: (context) =>
                                                    SmartServicesReleaseLaunch(
                                                        releases[i])))),
                              ]);
                            },
                          ))));
  }
}
