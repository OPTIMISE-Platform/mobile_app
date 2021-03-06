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

import 'package:badges/badges.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/widgets/settings/settings.dart';
import 'package:provider/provider.dart';

import '../notifications/notification_list.dart';

class MyAppBar {
  final String _title;

  const MyAppBar(this._title);

  static Widget _notifications(BuildContext context) {
    return Consumer<AppState>(
      builder: (_, __, ___) {
        AppState().initNotifications(context);
        AppState().checkMessageDisplay(context);
        final unread = AppState().notifications
            .where((element) => !element.isRead)
            .toList(growable: false)
            .length;
        return PlatformIconButton(
          icon: Badge(
            child: const Icon(Icons.notifications),
            badgeContent: Text(unread.toString()),
            showBadge: unread > 0,
          ),
          onPressed: () {
            Navigator.push(
              context,
              platformPageRoute(
                context: context,
                builder: (context) => const NotificationList(),
              ),
            );
          },
          cupertino: (_, __) => CupertinoIconButtonData(padding: EdgeInsets.zero),
        );
      },
    );
  }

  static Widget settings(BuildContext context) {
    return PlatformIconButton(
      icon: Icon(PlatformIcons(context).settings),
      onPressed: () {
        Navigator.push(
          context,
          platformPageRoute(
            context: context,
            builder: (context) => const Settings(),
          ),
        );
      },
      cupertino: (_, __) => CupertinoIconButtonData(padding: EdgeInsets.zero),
    );
  }

  static List<Widget> getDefaultActions(BuildContext context) {
    final List<Widget> actions = [
      _notifications(context),
      settings(context),
    ];
    return actions;
  }

  PlatformAppBar getAppBar(BuildContext context, [List<Widget>? trailingActions, Widget? leading]) {
    return PlatformAppBar(
      title: PlatformWidget(material: (_, __) => Text(_title, overflow: TextOverflow.fade),
          cupertino: (_, __) => Text(_title, style: const TextStyle(color: Colors.white), overflow: TextOverflow.fade)),
      cupertino: (_, __) =>
          CupertinoNavigationBarData(
            // Issue with cupertino where a bar with no transparency
            // will push the list down. Adding some alpha value fixes it (in a hacky way)
            backgroundColor: Colors.black,
          ),
      trailingActions: [
        ...trailingActions ?? [],
      ],
      leading: leading,
    );
  }
}
