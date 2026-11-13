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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:mobile_app/services/cache_helper.dart';
import 'package:mobile_app/shared/account_epoch.dart';
import 'package:mobile_app/services/favorites_migration.dart';
import 'package:mobile_app/theme.dart';
import 'package:mobile_app/widgets/shared/delay_circular_progress_indicator.dart';
import 'package:mobile_app/widgets/shared/toast.dart';
import 'package:mobile_app/widgets/tabs/device_tabs.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/exceptions/auth_exception.dart';
import 'package:mobile_app/services/auth.dart';
import 'package:mobile_app/widgets/shared/app_bar.dart';
import 'package:mobile_app/shared/error_reporter.dart';

class Home extends StatefulWidget {
  const Home({super.key});

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
  bool _imagePrecached = false;

  /// Whether the sign-in with a code shows instead of the password form.
  bool _withCode = false;
  DeviceCode? _code;
  String? _codeError;

  /// Advanced by every start and end of a sign-in with a code, so that a
  /// callback of an earlier one changes nothing.
  int _codeRun = 0;

  Future<void> _login() async {
    if (_user.isEmpty || _pw.isEmpty) return;
    try {
      final auth = context.read<Auth>();
      await auth.login(_user, _pw);
      _user = ""; // clear from memory
      _pw = ""; // clear from memory
      await _afterLogin();
    } catch (e, s) {
      if (e is AuthException && e.message == Auth.invalidCredentials) {
        Toast.showToastNoContext(Auth.invalidCredentials);
        setState(() {});
        return;
      }
      ErrorReporter.log("Login failed", e, s);
      Toast.showToastNoContext(e.toString());
    }
  }

  /// What follows every login the user started.
  Future<void> _afterLogin() async {
    // Before the refresh below, and here rather than only at startup: the
    // account is known for the first time now, and the refresh rewrites the
    // cached rows that still hold the favorites until this has run.
    try {
      await FavoritesMigration.run();
    } catch (e) {
      _logger.w("Moving favorites off the cache failed: $e");
    }
    // Refresh in the background: awaiting it here held the login spinner for
    // the whole multi-endpoint refresh, whose JSON parsing runs on the UI
    // isolate and stutters the spinner. The tabs fetch their first page
    // themselves right after the login transition; pushRefresh reloads them
    // once the complete cache has landed.
    unawaited(
      CacheHelper.refreshCache()
          .then((_) => AppState().pushRefresh())
          .catchError(
            (_) => Toast.showToastNoContext("Could not refresh cache"),
          ),
    );
  }

  Future<void> _loginWithCode() async {
    final auth = context.read<Auth>();
    final run = ++_codeRun;
    bool current() => mounted && run == _codeRun;
    setState(() {
      _withCode = true;
      _code = null;
      _codeError = null;
    });
    try {
      final signedIn = await auth.loginWithCode((code) {
        if (current()) setState(() => _code = code);
      });
      // Also when it ended without signing in, as for a session that came
      // first: the password form again after a later logout.
      if (current()) setState(_closeCodeView);
      if (signedIn) await _afterLogin();
    } on AuthException catch (e) {
      if (current()) setState(() => _codeError = e.message ?? "Sign-in failed");
    } catch (e, s) {
      ErrorReporter.log("Code login failed", e, s);
      if (current()) setState(() => _codeError = "Sign-in failed");
    }
  }

  void _cancelCodeLogin() {
    context.read<Auth>().cancelCodeLogin();
    setState(_closeCodeView);
  }

  void _closeCodeView() {
    _codeRun++;
    _withCode = false;
    _code = null;
    _codeError = null;
  }

  /// [button] anchors the share sheet, which an iPad requires.
  Future<void> _shareLink(DeviceCode code, BuildContext button) async {
    final box = button.findRenderObject();
    final origin = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    try {
      await SharePlus.instance.share(
        ShareParams(
          text: code.shareUri.toString(),
          sharePositionOrigin: origin,
        ),
      );
    } catch (e, s) {
      ErrorReporter.log("Could not share the sign-in link", e, s);
    }
  }

  List<Widget> _codeView(BuildContext context) {
    final cancel = TextButton(
      onPressed: _cancelCodeLogin,
      child: const Text("Cancel"),
    );
    final error = _codeError;
    if (error != null) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Spacing.lg),
          child: Text(error, textAlign: TextAlign.center),
        ),
        ElevatedButton(
          onPressed: _loginWithCode,
          child: const Text("New code"),
        ),
        cancel,
      ];
    }
    final code = _code;
    if (code == null) {
      return [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: Spacing.xl),
          child: DelayedCircularProgressIndicator(),
        ),
        cancel,
      ];
    }
    final textTheme = Theme.of(context).textTheme;
    return [
      const Padding(
        padding: EdgeInsets.only(top: Spacing.lg),
        child: Text(
          "Open this address on another device and enter the code.",
          textAlign: TextAlign.center,
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.md),
        child: SelectableText(
          code.userCode,
          textAlign: TextAlign.center,
          style: textTheme.displaySmall?.copyWith(letterSpacing: 2),
        ),
      ),
      SelectableText(
        code.verificationUri.toString(),
        textAlign: TextAlign.center,
      ),
      _CodeExpiry(code: code),
      Wrap(
        alignment: WrapAlignment.center,
        spacing: Spacing.sm,
        children: [
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code.userCode));
              Toast.showToastNoContext("Code copied");
            },
            icon: const Icon(Icons.copy),
            label: const Text("Copy code"),
          ),
          Builder(
            builder: (button) => OutlinedButton.icon(
              onPressed: () => _shareLink(code, button),
              icon: const Icon(Icons.share),
              label: const Text("Share link"),
            ),
          ),
        ],
      ),
      cancel,
    ];
  }

  TextFormField _passwordField() {
    return TextFormField(
      decoration: InputDecoration(
        hintText: "Password",
        suffixIcon: _visibilityButton(),
      ),
      keyboardType: TextInputType.visiblePassword,
      obscureText: _pwHidden,
      onChanged: (value) => setState(() => _pw = value),
      onFieldSubmitted: (_) => _login(),
      initialValue: _pw,
      autofillHints: const [AutofillHints.password],
    );
  }

  Widget _visibilityButton() {
    return IconButton(
        icon: Icon(_pwHidden ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _pwHidden = !_pwHidden));
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    if (_withCode) Auth().cancelCodeLogin();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_imagePrecached) {
      _imagePrecached = true;
      precacheImage(const AssetImage('assets/icon/icon.png'), context);
    }
  }

  @override
  Widget build(BuildContext context) {
    const appBar = MyAppBar("Login");
    return Consumer<Auth>(
      builder: (context, auth, child) {
        // loggedIn wins over loggingIn: after the early trust in Auth.init a
        // backend call can lock the login mutex while the client setup is
        // still running — gating on loggingIn first would unmount DeviceTabs
        // and bring the login spinner back for the whole token refresh.
        // Keyed by the epoch, so an account change under mounted tabs
        // remounts them: several screens read their configuration only when
        // they mount.
        if (auth.loggedIn) {
          return DeviceTabs(key: ValueKey(AccountEpoch.current));
        }
        if (!auth.isInitialized || auth.loggingIn) {
          return Scaffold(
            appBar: appBar.getAppBar(context, []),
            body: const Center(child: DelayedCircularProgressIndicator()),
          );
        }
        // Back leaves the sign-in with a code, not the app.
        return PopScope(
          canPop: !_withCode,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _cancelCodeLogin();
          },
          child: Scaffold(
            appBar: appBar.getAppBar(context, [MyAppBar.settings(context)]),
            body: Container(
              padding: Spacing.inset * 3,
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    Image.asset(
                      "assets/icon/icon.png",
                      width: MediaQuery.of(context).size.width * 0.4,
                    ),
                    if (_withCode)
                      ..._codeView(context)
                    else ...[
                      TextFormField(
                        decoration: const InputDecoration(hintText: "Username"),
                        keyboardType: TextInputType.text,
                        onChanged: (value) => setState(() => _user = value),
                        onFieldSubmitted: (_) => _login(),
                        initialValue: _user,
                        autofocus: true,
                        autofillHints: const [AutofillHints.username],
                      ),
                      _passwordField(),
                      ElevatedButton(
                        onPressed: _pw.isEmpty || _user.isEmpty
                            ? null
                            : () => _login(),
                        child: const Text("Login"),
                      ),
                      TextButton(
                        onPressed: _loginWithCode,
                        child: const Text("Sign in with a code"),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The time left until [code] expires, ticking every second.
class _CodeExpiry extends StatefulWidget {
  const _CodeExpiry({required this.code});

  final DeviceCode code;

  @override
  State<_CodeExpiry> createState() => _CodeExpiryState();
}

class _CodeExpiryState extends State<_CodeExpiry> {
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rounded up, so 0:00 shows only once the code has expired.
    final seconds = (widget.code.remaining.inMilliseconds + 999) ~/ 1000;
    final clock =
        "${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, "0")}";
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
      child: Text(
        "Expires in $clock",
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
