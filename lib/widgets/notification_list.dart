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

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:intl/intl.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/app_bar.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';

class NotificationList extends StatelessWidget {
  const NotificationList({Key? key}) : super(key: key);
  static final _format = DateFormat.yMd().add_jms();

  @override
  Widget build(BuildContext context) {
    const appBar = MyAppBar("Notifications");

    return Consumer<AppState>(builder: (context, state, child) {
      state.checkMessageDisplay(context);
      final List<Widget> appBarActions = [];

      if (kIsWeb) {
        appBarActions.add(PlatformIconButton(
          onPressed: () => state.loadNotifications(context),
          icon: const Icon(Icons.refresh),
          cupertino: (_, __) => CupertinoIconButtonData(padding: EdgeInsets.zero),
        ));
      }

      return PlatformScaffold(
          appBar: appBar.getAppBar(context, appBarActions),
          body: RefreshIndicator(
              onRefresh: () => state.loadNotifications(context),
              child: Scrollbar(
                  child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                itemCount: state.notifications.length,
                itemBuilder: (BuildContext context, int i) {
                  return Column(
                    children: [
                      const Divider(),
                      ListTile(
                          title: Text(state.notifications[i].title),
                          subtitle: Text(_format.format(state.notifications[i].createdAt())),
                          leading: state.notifications[i].isRead
                              ? /*const SizedBox.shrink()*/ null
                              : const Icon(Icons.circle_notifications, color: MyTheme.warnColor),
                          trailing: PlatformPopupMenu(
                            icon: Icon(PlatformIcons(context).ellipsis),
                            options: [
                              PopupMenuOption(
                                  label: 'Delete',
                                  onTap: (_) async {
                                    final confirmed = await showPlatformDialog(
                                      context: context,
                                      builder: (_) => PlatformAlertDialog(
                                        title: const Text('Confirmation'),
                                        content: const Text("Do you want to permanently delete this notification?"),
                                        actions: <Widget>[
                                          PlatformDialogAction(
                                            child: PlatformText('Cancel'),
                                            onPressed: () => Navigator.pop(context, false),
                                          ),
                                          PlatformDialogAction(child: PlatformText('OK'), onPressed: () => Navigator.pop(context, true)),
                                        ],
                                      ),
                                    );
                                    if (confirmed is bool && confirmed) {
                                      await state.deleteNotification(context, i);
                                    }
                                  },
                                  cupertino: (_, __) => CupertinoPopupMenuOptionData(isDestructiveAction: true)),
                              PopupMenuOption(
                                  label: 'Delete All',
                                  onTap: (_) async {
                                    final confirmed = await showPlatformDialog(
                                      context: context,
                                      builder: (_) => PlatformAlertDialog(
                                        title: const Text('Confirmation'),
                                        content: const Text("Do you want to permanently delete all notifications?"),
                                        actions: <Widget>[
                                          PlatformDialogAction(
                                            child: PlatformText('Cancel'),
                                            onPressed: () => Navigator.pop(context, false),
                                          ),
                                          PlatformDialogAction(child: PlatformText('OK'), onPressed: () => Navigator.pop(context, true)),
                                        ],
                                      ),
                                    );
                                    if (confirmed is bool && confirmed) {
                                      await state.deleteAllNotifications(context);
                                    }
                                  },
                                  cupertino: (_, __) => CupertinoPopupMenuOptionData(isDestructiveAction: true)),
                              PopupMenuOption(
                                label: 'Toggle Read',
                                onTap: (_) async {
                                  state.notifications[i].isRead = !state.notifications[i].isRead;
                                  await state.updateNotifications(context, i);
                                },
                              ),
                              PopupMenuOption(
                                label: 'Mark all Read',
                                onTap: (_) async {
                                  for (var i = 0; i < state.notifications.length; i++) {
                                    if (!state.notifications[i].isRead) {
                                      state.notifications[i].isRead = true;
                                      await state.updateNotifications(context, i);
                                    }
                                  }
                                },
                              ),
                            ],
                            cupertino: (_, __) => CupertinoPopupMenuData(
                                cancelButtonData: CupertinoPopupMenuCancelButtonData(
                              child: const Text('Close'),
                              onPressed: () => {},
                            )),
                          ),
                          onTap: () {
                            if (!state.notifications[i].isRead) {
                              state.notifications[i].isRead = true;
                              state.updateNotifications(context, i);
                            }
                            state.notifications[i].show(context);
                          })
                    ],
                  );
                },
              ))));
    });
  }
}
