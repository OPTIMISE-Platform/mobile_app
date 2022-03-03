import 'package:flutter/material.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:mobile_app/widgets/app_bar.dart';


class PageSpinner extends StatefulWidget {
  final String _title;

  const PageSpinner(this._title, {Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _PageSpinnerState(_title);
  }
}

class _PageSpinnerState extends State<PageSpinner> {
  late final MyAppBar _appBar;
  final String _title;

  _PageSpinnerState(this._title) {
    _appBar = MyAppBar();
    _appBar.setTitle(_title);
  }

  @override
  Widget build(BuildContext context) {
    return PlatformScaffold(
      //backgroundColor: MyTheme.appColor,
      appBar: _appBar.getAppBar(context),
      body: Center(
          child: PlatformCircularProgressIndicator(),
      ),
    );
  }
}

