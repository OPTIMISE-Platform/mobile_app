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

import 'package:flutter/foundation.dart';

/// A [ChangeNotifier] with a public notify, held per model entity (device,
/// group) so a change to that entity's own mutable UI state (value,
/// transitioning, connection, favorite) rebuilds only the widgets bound to it
/// — instead of every `Consumer<AppState>` in the app via the global notifier.
class EntityNotifier extends ChangeNotifier {
  void notifyChanged() => notifyListeners();
}
