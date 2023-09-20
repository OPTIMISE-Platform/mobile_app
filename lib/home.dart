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
import 'package:logger/logger.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/shared/toast.dart';
import 'package:mobile_app/widgets/tabs/device_tabs.dart';
import 'package:openidconnect_platform_interface/openidconnect_platform_interface.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'services/auth.dart';
import 'widgets/shared/app_bar.dart';

class Home extends StatefulWidget {
  const Home({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  static final _logger = Logger();

  _HomeState() {
    _logger.d("OPTIMISE App Homescreen loaded");
  }

  String _user = "";
  String _pw = "";
  bool _pwHidden = true;
  bool _loginChecked = false;

  _login() async {
    if (_user.isEmpty || _pw.isEmpty) return;
    try {
      await Auth().login(_user, _pw);
      _user = ""; // clear from memory
      _pw = ""; // clear from memory
      await CacheHelper.refreshCache();
      AppState().pushRefresh();
    } on AuthenticationException catch (e) {
      if (e.errorMessage != null && e.errorMessage!.contains("Invalid user credentials")) {
        Toast.showToastNoContext("Invalid user credentials");
        setState(() {});
      } else {
        rethrow;
      }
    } catch (e) {
      Toast.showToastNoContext(e.toString());
    }
  }

  PlatformTextFormField _passwordField() {
    return PlatformTextFormField(
      hintText: "Password",
      keyboardType: TextInputType.visiblePassword,
      obscureText: _pwHidden,
      onChanged: (value) => setState(() => _pw = value),
      onFieldSubmitted: (_) => _login(),
      initialValue: _pw,
      autofillHints: const [AutofillHints.password],
      material: (context, _) => MaterialTextFormFieldData(
        decoration: InputDecoration(
          suffixIcon: PlatformIconButton(icon: _visibilityButton()),
        ),
      ),
    );
  }

  Widget _visibilityButton() {
    return PlatformIconButton(
        icon: Icon(_pwHidden ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _pwHidden = !_pwHidden));
  }

  _checklogin() async {
    await Auth().refreshToken();
    setState(() {
      _loginChecked = true;
    });
  }

  @override
  void initState() {
    super.initState();
    _checklogin();
  }

  @override
  Widget build(BuildContext context) {
    final appBar = MyAppBar(_loginChecked ? "Login" : "Loading");
    return Consumer<Auth>(
      builder: (context, auth, child) {
        return auth.loggedIn
            ? const DeviceTabs()
            : PlatformScaffold(
                appBar: appBar.getAppBar(context, [MyAppBar.settings(context)]),
                body: auth.loggingIn || !_loginChecked
                    ? const Center(child: DelayedCircularProgressIndicator())
                    : Container(
                        padding: MyTheme.inset * 3,
                        child: SingleChildScrollView(
                            child: Column(children: [
                          Image.asset("assets/icon/icon.png", width: MediaQuery.of(context).size.width * 0.4),
                          PlatformTextFormField(
                            hintText: "Username",
                            keyboardType: TextInputType.text,
                            onChanged: (value) => setState(() => _user = value),
                            onFieldSubmitted: (_) => _login(),
                            initialValue: _user,
                            autofocus: true,
                            autofillHints: const [AutofillHints.username],
                          ),
                          PlatformWidget(
                              material: (_, __) => _passwordField(),
                              cupertino: (context, __) =>
                                  Row(mainAxisSize: MainAxisSize.min, children: [Expanded(child: _passwordField()), _visibilityButton()])),
                          PlatformElevatedButton(
                            onPressed: _pw.isEmpty || _user.isEmpty ? null : () => _login(),
                            child: const Text("Login"),
                          ),
                        ])),
                      ));
      },
    );
  }
}
