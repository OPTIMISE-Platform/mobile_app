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

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/models/mgw.dart';
import 'package:mobile_app/services/mgw/storage.dart';

/// Keeps [gateway] on the stored entry it stands for while
/// `AppState.gateways` changes - an address refresh, pairing again - so what
/// the widget shows and does addresses the gateway where it is now.
mixin FollowsStoredGateway<T extends StatefulWidget> on State<T> {
  late MGW gateway;

  /// True while the widget changes the entry itself and must not be moved.
  bool get holdsGateway => false;

  /// Called after [gateway] moved to a changed entry.
  void gatewayChanged(MGW previous) {}

  void followGateway(MGW initial) {
    gateway = initial;
    AppState().addListener(_follow);
  }

  @override
  void dispose() {
    AppState().removeListener(_follow);
    super.dispose();
  }

  void _follow() {
    if (!mounted || holdsGateway) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _follow());
      return;
    }
    final current = MgwStorage.resolve(gateway, AppState().gateways);
    if (current == null || MgwStorage.isSameEntry(current, gateway)) return;
    final previous = gateway;
    setState(() => gateway = current);
    gatewayChanged(previous);
  }
}
