import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_app/app_state.dart';

class DeviceListFavoritesController {
  final AppState state;

  bool _initialized = false;

  StreamSubscription? refreshSub;

  DeviceListFavoritesController(this.state);

  void init(BuildContext context) {
    if (!_initialized) {
      _initialized = true;

      if (state.initialized && state.devices.isEmpty) {
        state.loadDevices(context);
      }
    }

    refreshSub ??= state.refreshPressed.listen((_) {
      state.refreshDevices(context);
    });
  }

  void dispose() {
    refreshSub?.cancel();
  }

  void onResume(BuildContext context) {
    state.refreshDevices(context);
  }
}