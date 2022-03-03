import 'package:flutter/widgets.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/widgets/app_bar.dart';
import 'package:mobile_app/widgets/device_list.dart';

import 'services/auth.dart';

class Home extends StatefulWidget {
  const Home({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _HomeState();
  }
}

class _HomeState extends State<Home> {
  late final MyAppBar _appBar;
  late Future _refresher;
  late bool _loggedIn;
  late bool _loggingIn;
  final _logger = Logger();
  
  static const _refreshInterval = Duration(seconds: 2);

  _HomeState() {
    _logger.d("OPTIMISE App Homescreen loaded");
    _appBar = MyAppBar();
    _appBar.setTitle("Login");
    _loggedIn = Auth.tokenValid();
    _loggingIn = Auth.loggingIn();
    _refresher = Future.delayed(_refreshInterval, _refresh);
  }

  _refresh() {
    if (Auth.tokenValid() != _loggedIn || Auth.loggingIn() != _loggingIn) {
      setState(() {
        _loggedIn = Auth.tokenValid();
        _loggingIn = Auth.loggingIn();
      });
    }
    _refresher = Future.delayed(_refreshInterval, _refresh);
  }

  @override
  void dispose() {
    _refresher.ignore();
    super.dispose();
  }

  login(BuildContext context) async {
    await Auth.login(context);
    if (mounted) {
      setState(() {});
    }
  }

  logout(BuildContext context) async {
    await Auth.logout(context);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return _loggedIn
        ? DeviceList()
        : PlatformScaffold(
            //backgroundColor: MyTheme.appColor,
            appBar: _appBar.getAppBar(context),
            body: Center(
                child: _loggingIn ?
                PlatformCircularProgressIndicator() :
                PlatformTextButton(
                    child: const Text("Login"),
                    onPressed: () => login(context))),
          );
  }
}
