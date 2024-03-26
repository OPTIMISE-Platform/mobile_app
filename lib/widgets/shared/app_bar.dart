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
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/services/settings.dart' as SettingsService;
import 'package:mobile_app/widgets/settings/settings.dart';
import 'package:provider/provider.dart';

import 'package:mobile_app/services/app_update.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/notifications/notification_list.dart';

class MyAppBar {
  final String _title;

  const MyAppBar(this._title);

  static Widget _notifications(BuildContext context) {
    return Consumer<AppState>(
      builder: (_, __, ___) {
        AppState().initNotifications(context);
        AppState().checkMessageDisplay(context);
        final unread = AppState()
            .notifications
            .where((element) => !element.isRead)
            .toList(growable: false)
            .length;
        return PlatformIconButton(
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text(unread.toString()),
            textColor: Colors.white,
            child: const Icon(Icons.notifications),
          ),
          onPressed: () {
            Navigator.push(
              context,
              platformPageRoute(
                context: context,
                settings: const RouteSettings(
                    name: NotificationList.preferredRouteName),
                builder: (context) => const NotificationList(),
              ),
            );
          },
          cupertino: (_, __) =>
              CupertinoIconButtonData(padding: EdgeInsets.zero),
        );
      },
    );
  }

  static PreferredSizeWidget? _localMode(BuildContext context) {
    bool? localMode = SettingsService.Settings.getLocalMode();

    return localMode != true ? null : const PreferredSize(
            preferredSize: Size(128, 23),
            child: ColoredBox(
                color: Colors.black,
                child: (
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.lan_outlined,
                          color: Colors.white,
                        ),
                        Text(
                          " Local Mode",
                          style: TextStyle(color: Colors.white),
                        )],
                    )
                )
            )
    );
  }

  static Widget _updateIcon(BuildContext context) {
    bool? hasUpdate =
        AppUpdater.updateAvailableSync(cacheAge: const Duration(days: 1));

    final future = hasUpdate != null
        ? null
        : AppUpdater.updateAvailable(cacheAge: const Duration(days: 1));
    return StatefulBuilder(builder: (context, setState) {
      future?.then((value) => {
            if (value != null && value != hasUpdate)
              {setState(() => hasUpdate = value)}
          });
      return hasUpdate != true ? const SizedBox.shrink() : UpdateIcon();
    });
  }

  static Widget settings(BuildContext context) {
    return PlatformIconButton(
      icon: Icon(PlatformIcons(context).settings),
      onPressed: () {
        Navigator.push(
          context,
          platformPageRoute(
            context: context,
            builder: (context) => Settings(),
          ),
        );
      },
      cupertino: (_, __) => CupertinoIconButtonData(padding: EdgeInsets.zero),
    );
  }

  static List<Widget> getDefaultActions(BuildContext context) {
    final List<Widget> actions = [
      _updateIcon(context),
      _notifications(context),
      settings(context),
    ];
    return actions;
  }

  PlatformAppBar getAppBar(BuildContext context,
      [List<Widget>? trailingActions, Widget? leading]) {
    return PlatformAppBar(
      title: PlatformWidget(
          material: (_, __) => Text(_title, overflow: TextOverflow.fade),
          cupertino: (_, __) => Text(
              _title +
                  (SettingsService.Settings.getLocalMode() ? " (Offline)" : ""),
              style: const TextStyle(color: Colors.white),
              overflow: TextOverflow.fade)),
      cupertino: (_, __) => CupertinoNavigationBarData(
        // Issue with cupertino where a bar with no transparency
        // will push the list down. Adding some alpha value fixes it (in a hacky way)
        backgroundColor: Colors.black,
      ),
      material: (_, __) => MaterialAppBarData(
        bottom: _localMode(context),
      ),
      trailingActions: [
        ...trailingActions ?? [],
      ],
      leading: leading,
    );
  }
}

class UpdateIcon extends StatefulWidget {
  @override
  _UpdateIconState createState() => _UpdateIconState();
}

class _UpdateIconState extends State<UpdateIcon>
    with SingleTickerProviderStateMixin {
  late Animation<Color?> animation;
  late AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
        duration: const Duration(seconds: 1, milliseconds: 200), vsync: this);
    animation = ColorTween(begin: MyTheme.textColor!, end: MyTheme.appColor)
        .animate(controller)
      ..addListener(() {
        setState(() {
          // The state that has changed here is the animation object’s value.
        });
      });
    controller.repeat(reverse: true);
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.system_update_alt, color: animation.value),
      onPressed: () => AppUpdater.showUpdateDialog(context),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
