/*
 * Copyright 2026 InfAI (CC SES)
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

/// Calls [onResumed] when the app returns to the foreground while this widget
/// is the current route.
///
/// Fourteen widgets each registered the lifecycle observer themselves and
/// repeated the same three-part condition, and only one of them checked
/// [mounted]: the observer is removed in `dispose`, so a callback can still
/// arrive for a State that is deactivated but not yet disposed, and
/// `ModalRoute.of` throws for one of those.
///
/// The observer is a separate object rather than the State itself, so a widget
/// using this does not have to also mix in [WidgetsBindingObserver] and cannot
/// forget the add/remove pair.
mixin ResumeRefreshMixin<T extends StatefulWidget> on State<T> {
  late final _ResumeObserver _resumeObserver =
      _ResumeObserver(_onLifecycleState);

  /// Reload whatever this widget shows. Only called while it is on screen and
  /// on the current route, so it never has to guard against either.
  void onResumed();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(_resumeObserver);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_resumeObserver);
    super.dispose();
  }

  void _onLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    onResumed();
  }
}

class _ResumeObserver extends WidgetsBindingObserver {
  _ResumeObserver(this._onState);

  final void Function(AppLifecycleState) _onState;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _onState(state);
}
