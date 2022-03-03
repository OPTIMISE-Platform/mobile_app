import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:mobile_app/widgets/settings.dart';

class MyAppBar {
  String _title = 'OPTIMISE';

  setTitle(String newTitle) {
    _title = newTitle;
  }

  static List<Widget> getDefaultActions(BuildContext context) {
    return [
      PlatformIconButton(
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
      )
    ];
  }

  PlatformAppBar getAppBar(BuildContext context, [List<Widget>? trailingActions]) {
      return PlatformAppBar(
        title: Text(_title),
        cupertino: (_, __) => CupertinoNavigationBarData(
          // Issue with cupertino where a bar with no transparency
          // will push the list down. Adding some alpha value fixes it (in a hacky way)
          backgroundColor: Colors.black,
        ),
        trailingActions: [
          ...trailingActions ?? [],
        ],
    );
  }
}
