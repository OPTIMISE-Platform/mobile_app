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
import 'package:mobile_app/services/notifications.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/toast.dart';
import 'package:provider/provider.dart';

import "package:mobile_app/models/notification.dart" as app;
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/widgets/shared/app_bar.dart';

class NotificationList extends StatefulWidget {
  static const preferredRouteName = "notifications";

  const NotificationList({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _NotificationListState();
}

class _NotificationListState extends State<NotificationList> {
  static final _format = DateFormat.yMd().add_jms();

  final Set<app.Notification> _selected = {};
  bool _selectionMode = false;

  @override
  Widget build(BuildContext context) {
    final appBar = MyAppBar(
        _selectionMode ? _selected.length.toString() : "Notifications");

    return Consumer<AppState>(builder: (context, state, child) {
      state.checkMessageDisplay(context);
      final List<Widget> appBarActions = [];

      if (kIsWeb) {
        appBarActions.add(PlatformIconButton(
          onPressed: !NotificationsService.isAvailable()
              ? null
              : () => state.loadNotifications(context),
          icon: const Icon(Icons.refresh),
          cupertino: (_, __) =>
              CupertinoIconButtonData(padding: EdgeInsets.zero),
        ));
      }

      if (_selectionMode) {
        appBarActions.addAll([
          PlatformIconButton(
            onPressed: () => setState(() {
              _selected.clear();
              _selectionMode = false;
            }),
            icon: Icon(PlatformIcons(context).clear),
            cupertino: (_, __) =>
                CupertinoIconButtonData(padding: EdgeInsets.zero),
          ),
          PlatformIconButton(
            onPressed: () =>
                setState(() => _selected.addAll(state.notifications)),
            icon: Icon(PlatformIcons(context).addCircledOutline),
            cupertino: (_, __) =>
                CupertinoIconButtonData(padding: EdgeInsets.zero),
          ),
          PlatformIconButton(
            onPressed: !NotificationsService.isAvailable()
                ? null
                : () async {
                    final List<Future> futures = [];
                    for (var element in _selected) {
                      if (!element.isRead) {
                        element.isRead = true;
                        futures.add(state.updateNotifications(
                            context, state.notifications.indexOf(element)));
                      }
                    }
                    await Future.wait(futures);
                    setState(() {
                      _selected.clear();
                      _selectionMode = false;
                    });
                  },
            icon: const Icon(Icons.mark_email_read),
            cupertino: (_, __) =>
                CupertinoIconButtonData(padding: EdgeInsets.zero),
          ),
          PlatformIconButton(
            onPressed: !NotificationsService.isAvailable()
                ? null
                : () async {
                    final List<Future> futures = [];
                    for (var element in _selected) {
                      if (element.isRead) {
                        element.isRead = false;
                        futures.add(state.updateNotifications(
                            context, state.notifications.indexOf(element)));
                      }
                    }
                    await Future.wait(futures);
                    setState(() {
                      _selected.clear();
                      _selectionMode = false;
                    });
                  },
            icon: const Icon(Icons.mark_email_unread),
            cupertino: (_, __) =>
                CupertinoIconButtonData(padding: EdgeInsets.zero),
          ),
          PlatformIconButton(
            onPressed: !NotificationsService.isAvailable()
                ? null
                : () async {
                    final confirmed = await showPlatformDialog(
                      context: context,
                      builder: (_) => PlatformAlertDialog(
                        title: const Text('Confirmation'),
                        content: const Text(
                            "Do you want to permanently delete selected notifications?"),
                        actions: <Widget>[
                          PlatformDialogAction(
                            child: PlatformText('Cancel'),
                            onPressed: () => Navigator.pop(context, false),
                          ),
                          PlatformDialogAction(
                              child: PlatformText('OK'),
                              cupertino: (_, __) => CupertinoDialogActionData(
                                  isDestructiveAction: true),
                              onPressed: () => Navigator.pop(context, true)),
                        ],
                      ),
                    );
                    if (confirmed is bool && confirmed) {
                      await state.deleteNotifications(this.context,
                          _selected.map((e) => e.id).toList(growable: false));
                      setState(() {
                        _selected.clear();
                        _selectionMode = false;
                      });
                    }
                  },
            icon: Icon(PlatformIcons(context).delete),
            cupertino: (_, __) =>
                CupertinoIconButtonData(padding: EdgeInsets.zero),
          ),
        ]);
      }

      return PlatformScaffold(
          appBar: appBar.getAppBar(context, appBarActions),
          body: RefreshIndicator(
              onRefresh: () async {
                HapticFeedbackProxy.lightImpact();
                state.loadNotifications(context);
              },
              child: Scrollbar(
                  child: state.notifications.isEmpty
                      ? const Center(child: Text("No Notifications"))
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: MyTheme.inset,
                          itemCount: state.notifications.length,
                          itemBuilder: (BuildContext context, int i) {
                            return Column(
                              children: [
                                i > 0
                                    ? const Divider()
                                    : const SizedBox.shrink(),
                                Dismissible(
                                    background: Container(
                                      alignment: Alignment.centerRight,
                                      padding: MyTheme.inset,
                                      color: MyTheme.warnColor,
                                      child: Icon(
                                        PlatformIcons(context).delete,
                                        color: Colors.white,
                                      ),
                                    ),
                                    confirmDismiss: (_) {
                                      final b = NotificationsService.isAvailable();
                                      if (!b) {
                                        Toast.showToastNoContext("Currently unavailable");
                                      }
                                      return Future.value(
                                          b);
                                    },
                                    direction: DismissDirection.endToStart,
                                    onDismissed: (_) => state
                                        .deleteNotifications(context,
                                            [state.notifications[i].id]),
                                    key: ValueKey<String>(
                                        state.notifications[i].id),
                                    child: ListTile(
                                      leading: !_selectionMode
                                          ? null
                                          : Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                  Icon(
                                                    _selected.contains(state
                                                            .notifications[i])
                                                        ? PlatformIcons(context)
                                                            .checkMarkCircledSolid
                                                        : Icons.circle_outlined,
                                                    color: MyTheme.appColor,
                                                  )
                                                ]),
                                      title: Row(
                                        children: [
                                          Text(state.notifications[i].title),
                                          Badge(
                                            label: const Icon(
                                              Icons.circle_notifications,
                                              size: 12,
                                              color: MyTheme.warnColor,
                                            ),
                                            isLabelVisible:
                                                !state.notifications[i].isRead,
                                            alignment:
                                                AlignmentDirectional.topCenter,
                                            largeSize: 16,
                                            backgroundColor: Colors.transparent,
                                            child: state.notifications[i].isRead
                                                ? null
                                                : const Text(""),
                                          )
                                        ],
                                      ),
                                      subtitle: Text(_format.format(
                                          state.notifications[i].createdAt())),
                                      onTap: () {
                                        if (_selectionMode) {
                                          setState(() {
                                            _selected.contains(
                                                    state.notifications[i])
                                                ? _selected.remove(
                                                    state.notifications[i])
                                                : _selected.add(
                                                    state.notifications[i]);
                                          });
                                        } else {
                                          if (!state.notifications[i].isRead) {
                                            state.notifications[i].isRead =
                                                true;
                                            state.updateNotifications(
                                                context, i);
                                          }
                                          state.notifications[i].show(context);
                                        }
                                      },
                                      onLongPress: _selectionMode
                                          ? null
                                          : () {
                                              setState(() {
                                                _selectionMode = true;
                                                _selected.add(
                                                    state.notifications[i]);
                                              });
                                            },
                                    ))
                              ],
                            );
                          },
                        ))));
    });
  }
}
