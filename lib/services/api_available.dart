/*
 * Copyright 2023 InfAI (CC SES)
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

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:mobile_app/app_state.dart';
import 'package:mobile_app/services/settings.dart';

class ApiAvailableService {
  bool _offline = false;

  static final _instance = ApiAvailableService._internal();

  factory ApiAvailableService() => _instance;

  ApiAvailableService._internal() {
    Connectivity().onConnectivityChanged.listen((event) {
      final offline = event == ConnectivityResult.none;
      if (offline != _offline) {
        _offline = offline;
        AppState().notifyListeners();
      }
    });
    Timer.periodic(const Duration(seconds: 10), (timer) async {
      // not all connectivity changes are recognized, checking periodically
      final offline = await Connectivity().checkConnectivity() == ConnectivityResult.none;
      if (offline != _offline) {
        _offline = offline;
        AppState().notifyListeners();
      }
    });
  }

  // performance evaluated, adds less than 2 ms to each request
  bool isAvailable(String uri) {
    if (_offline) {
      return false;
    }
    // TODO request from backend, cache, match against routes
    final parsedUri = Uri.parse(uri);
    try {
      AppState().networks.firstWhere(
          (element) => element.localService?.host == parsedUri.host);
      // a network has the requested host
      return true;
    } on StateError {
      // pass
    }
    final rv = !Settings.getLocalMode();
    return rv;
  }
}
