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
