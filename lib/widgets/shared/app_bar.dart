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
    return Selector<AppState, int>(
      selector: (_, state) {
        state.initNotifications(context);
        state.checkMessageDisplay(context);
        // Count without allocating an intermediate list.
        return state.notifications.where((element) => !element.isRead).length;
      },
      builder: (_, unread, __) {
        return IconButton(
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text(unread.toString()),
            textColor: Colors.white,
            child: const Icon(Icons.notifications),
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                settings: const RouteSettings(
                    name: NotificationList.preferredRouteName),
                builder: (context) => const NotificationList(),
              ),
            );
          },
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
      return hasUpdate != true ? const SizedBox.shrink() : const UpdateIcon();
    });
  }

  static Widget settings(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.settings),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const Settings(),
          ),
        );
      },
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

  AppBar getAppBar(BuildContext context,
      [List<Widget>? actions, Widget? leading, PreferredSizeWidget? bottomExtra]) {
    return AppBar(
      title: Text(_title, overflow: TextOverflow.fade),
      // Local mode banner and a caller-supplied bottom (e.g. the Devices
      // segment bar) stack in one PreferredSize; most call sites pass neither.
      bottom: _combinedBottom(context, bottomExtra),
      actions: actions,
      leading: leading,
    );
  }

  static PreferredSizeWidget? _combinedBottom(
      BuildContext context, PreferredSizeWidget? extra) {
    final localMode = _localMode(context);
    if (localMode == null && extra == null) return null;
    final height =
        (localMode?.preferredSize.height ?? 0) + (extra?.preferredSize.height ?? 0);
    return PreferredSize(
      preferredSize: Size.fromHeight(height),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (localMode != null) localMode,
        if (extra != null) extra,
      ]),
    );
  }
}

class UpdateIcon extends StatefulWidget {
  const UpdateIcon({super.key});

  @override
  _UpdateIconState createState() => _UpdateIconState();
}

class _UpdateIconState extends State<UpdateIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
        duration: const Duration(seconds: 1, milliseconds: 200), vsync: this);
    controller.repeat(reverse: true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    // Interpolated per frame from the current theme rather than a tween built
    // once, so a theme switch recolours the running animation.
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => IconButton(
        icon: Icon(Icons.system_update_alt,
            color: Color.lerp(colors.text, colors.appInk, controller.value)),
        onPressed: () => AppUpdater.showUpdateDialog(context),
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}
