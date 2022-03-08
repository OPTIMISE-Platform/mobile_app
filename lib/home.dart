import 'package:flutter/widgets.dart';
import 'package:flutter_platform_widgets/flutter_platform_widgets.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/widgets/app_bar.dart';
import 'package:mobile_app/widgets/device_list.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
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
  final _logger = Logger();

  _HomeState() {
    _logger.d("OPTIMISE App Homescreen loaded");
    _appBar = MyAppBar();
    _appBar.setTitle("Login");
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        return state.loggedIn()
            ? const DeviceList()
            : PlatformScaffold(
                //backgroundColor: MyTheme.appColor,
                appBar: _appBar.getAppBar(context),
                body: Center(
                  child: state.loggingIn()
                      ? PlatformCircularProgressIndicator()
                      : PlatformTextButton(
                          child: const Text("Login"),
                          onPressed: () => Auth.login(context, state),
                        ),
                ),
              );
      },
    );
  }
}
