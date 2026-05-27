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

import 'package:flutter/material.dart';

/// Allows any part of the app to trigger a full widget-tree restart
/// without needing a reference to [MyApp]'s state.
///
/// Usage from anywhere:
/// ```dart
/// RestartController.restart();
/// ```
class RestartController extends ChangeNotifier {
  static RestartController? _instance;

  RestartController._();

  static RestartController get instance {
    _instance ??= RestartController._();
    return _instance!;
  }

  /// Call this from anywhere to restart the app.
  static void restart() => RestartController.instance.notifyListeners();
}